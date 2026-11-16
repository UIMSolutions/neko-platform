/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// OData v4 endpoint for SAP Fiori (sap.ui.model.odata.v4.ODataModel).
///
///   GET    <base>/  ·  <base>/$metadata
///   GET    <base>/Services[?$filter&$orderby&$search&$select&$top&$skip&$count]  ·  /Services/$count
///   GET    <base>/Services('<id>')
///   POST   <base>/Services                 register
///   PATCH  <base>/Services('<id>')         Description, BaseUrl, HealthPath
///   DELETE <base>/Services('<id>')         only retired services
///   GET    <base>/Transfers[…]  ·  <base>/Transfers('<id>')
///   GET    <base>/Overview                 singleton
///   POST   <base>/<Action>                 ActivateService, SuspendService, RetireService,
///                                          CheckServiceHealth, ExportPackage, ImportPackage
///
/// $batch is not supported: configure the UI5 model with groupId "$direct".
module neko.service.platform.presentation.odata;

public import neko.service.platform.presentation.odata.model;
public import neko.service.platform.presentation.odata.query;

import std.algorithm : endsWith, startsWith;
import std.array : replace;
import std.conv : to;
import std.string : indexOf, strip;
import std.typecons : Nullable;
import vibe.data.json;
import vibe.http.common : HTTPMethod;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.core.log : logError;
import neko.service.platform.domain;
import neko.service.platform.application.dtos;
import neko.service.platform.ports.usecases;
import neko.service.platform.presentation.http : actorOf, writeError;

@safe:

/// Resource path after the service root: "Services", "Services('a')", "Services/$count".
struct ResourcePath {
  string name;
  string key;
  bool hasKey;
  bool countOnly;
}

ResourcePath parseResourcePath(string path) {
  ResourcePath r;
  auto p = path.strip("/");
  if (p.endsWith("/$count")) {
    r.countOnly = true;
    p = p[0 .. $ - "/$count".length];
  }
  if (p.indexOf('/') >= 0)
    throw new ValidationException("Navigation paths are not supported: " ~ path);
  auto open = p.indexOf('(');
  if (open < 0) {
    r.name = p;
    return r;
  }
  if (!p.endsWith(")"))
    throw new ValidationException("Invalid key in " ~ path);
  r.name = p[0 .. open];
  auto key = p[open + 1 .. $ - 1];
  auto eq = key.indexOf('=');
  if (eq >= 0)
    key = key[eq + 1 .. $];
  if (key.length >= 2 && key[0] == '\'' && key[$ - 1] == '\'')
    key = key[1 .. $ - 1].replace("''", "'");
  r.key = key;
  r.hasKey = key.length > 0;
  return r;
}

class PlatformODataController {
  private IManageServicesUseCase services;
  private ICheckServiceHealthUseCase health;
  private ITransferPackagesUseCase transfers;
  private IPlatformOverviewUseCase overview;
  private string basePath;
  private string metadata;

  this(IManageServicesUseCase services, ICheckServiceHealthUseCase health, ITransferPackagesUseCase transfers,
      IPlatformOverviewUseCase overview, string basePath) {
    this.services = services;
    this.health = health;
    this.transfers = transfers;
    this.overview = overview;
    this.basePath = basePath;
    while (this.basePath.length > 1 && this.basePath[$ - 1] == '/')
      this.basePath = this.basePath[0 .. $ - 1];
    this.metadata = buildMetadata();
  }

  void registerRoutes(URLRouter router) {
    router.get(basePath, &serviceDocument);
    router.get(basePath ~ "/", &serviceDocument);
    // UI5 fetches the CSRF token with "HEAD <service root>" before modifying requests.
    router.match(HTTPMethod.HEAD, basePath, &tokenProbe);
    router.match(HTTPMethod.HEAD, basePath ~ "/", &tokenProbe);
    router.get(basePath ~ "/$metadata", &serveMetadata);
    router.any(basePath ~ "/*", &handle);
  }

  void serviceDocument(HTTPServerRequest req, HTTPServerResponse res) {
    Json[] sets;
    foreach (e; entityTypes)
      sets ~= Json(["name": Json(e.set), "url": Json(e.set), "kind": Json(e.singleton ? "Singleton" : "EntitySet")]);
    auto body = Json.emptyObject;
    body["@odata.context"] = "$metadata";
    body["value"] = Json(sets);
    writeOData(res, 200, body);
  }

  /// Answers the token probe without issuing a token: CSRF protection is the
  /// approuter's job (xs-app.json "csrfProtection"), UI5 then sends no token.
  void tokenProbe(HTTPServerRequest req, HTTPServerResponse res) {
    res.headers["OData-Version"] = "4.0";
    res.statusCode = 200;
    res.writeVoidBody();
  }

  void serveMetadata(HTTPServerRequest req, HTTPServerResponse res) {
    res.headers["OData-Version"] = "4.0";
    res.writeBody(metadata, 200, "application/xml");
  }

  void handle(HTTPServerRequest req, HTTPServerResponse res) {
    try {
      auto path = parseResourcePath(req.requestPath.toString[basePath.length .. $]);
      if (findAction(path.name) !is null) {
        if (req.method != HTTPMethod.POST)
          throw new PlatformException(405, "Actions must be invoked with POST");
        invokeAction(path.name, readBody(req), actorOf(req, res), res);
        return;
      }
      auto def = findEntitySet(path.name);
      if (def is null)
        throw new NotFoundException("Resource", path.name);

      switch (req.method) {
      case HTTPMethod.GET:
      case HTTPMethod.HEAD:
        read(*def, path, req, res);
        break;
      case HTTPMethod.POST:
        if (def.set != "Services" || path.hasKey)
          throw new PlatformException(405, def.set ~ " cannot be created directly");
        auto created = services.register(toRegisterRequest(readBody(req)), actorOf(req, res));
        res.headers["Location"] = basePath ~ "/Services('" ~ created.id ~ "')";
        writeEntity(res, 201, "Services", toEntity(created));
        break;
      case HTTPMethod.PATCH:
        if (def.set != "Services" || !path.hasKey)
          throw new PlatformException(405, def.set ~ " cannot be updated");
        auto updated = services.update(path.key, toUpdateRequest(readBody(req)), actorOf(req, res));
        writeEntity(res, 200, "Services", toEntity(updated));
        break;
      case HTTPMethod.DELETE:
        if (def.set != "Services" || !path.hasKey)
          throw new PlatformException(405, def.set ~ " cannot be deleted");
        services.remove(path.key, actorOf(req, res));
        res.statusCode = 204;
        res.writeVoidBody();
        break;
      default:
        throw new PlatformException(405, "Method not allowed");
      }
    } catch (PlatformException e) {
      writeError(res, e.code, errorCode(e.code), e.msg);
    } catch (Exception e) {
      logError("odata: %s", e.msg);
      writeError(res, 500, "InternalError", e.msg);
    }
  }

  private void read(const EntityTypeDef def, ResourcePath path, HTTPServerRequest req, HTTPServerResponse res) {
    if (def.singleton) {
      writeEntity(res, 200, def.set, toEntity(overview.overview()), true);
      return;
    }
    if (path.hasKey) {
      auto entity = def.set == "Services" ? toEntity(services.get(path.key)) : toEntity(transfers.get(path.key));
      auto q = parseQuery(queryParams(req));
      writeEntity(res, 200, def.set, applySelect(entity, q, def.key));
      return;
    }

    Json[] all;
    if (def.set == "Services")
      foreach (s; services.list(ServiceQuery.init))
        all ~= toEntity(s);
    else
      foreach (t; transfers.list())
        all ~= toEntity(t);

    auto q = parseQuery(queryParams(req));
    auto filtered = applyFilter(all, q);
    if (path.countOnly) {
      res.headers["OData-Version"] = "4.0";
      res.writeBody(filtered.length.to!string, 200, "text/plain");
      return;
    }
    Json[] page;
    foreach (e; applyPaging(filtered, q))
      page ~= applySelect(e, q, def.key);

    auto body = Json.emptyObject;
    body["@odata.context"] = "$metadata#" ~ def.set;
    if (q.count)
      body["@odata.count"] = cast(long) filtered.length;
    body["value"] = Json(page);
    writeOData(res, 200, body);
  }

  private void invokeAction(string name, Json params, string actor, HTTPServerResponse res) {
    string param(string key) {
      if (auto v = key in params)
        if (v.type == Json.Type.string)
          return v.get!string;
      throw new ValidationException("Action " ~ name ~ " requires the parameter '" ~ key ~ "'");
    }

    switch (name) {
    case "ActivateService":
      return writeEntity(res, 200, "Services", toEntity(services.activate(param("ID"), actor)));
    case "SuspendService":
      return writeEntity(res, 200, "Services", toEntity(services.suspend(param("ID"), actor)));
    case "RetireService":
      return writeEntity(res, 200, "Services", toEntity(services.retire(param("ID"), actor)));
    case "CheckServiceHealth":
      return writeEntity(res, 200, "Services", toEntity(health.check(param("ID"))));
    case "ExportPackage":
      auto request = ExportPackageRequest(param("Name"), param("TargetDomain"), param("Payload"));
      return writeEntity(res, 200, "Transfers", toEntity(transfers.exportPackage(request, actor)));
    case "ImportPackage":
      return writeEntity(res, 200, "Transfers",
        toEntity(transfers.importPackage(ImportPackageRequest(param("Document")), actor)));
    default:
      throw new NotFoundException("Action", name);
    }
  }

  private static RegisterServiceRequest toRegisterRequest(Json body) {
    RegisterServiceRequest r;
    r.name = str(body, "Name");
    r.description = str(body, "Description");
    r.classification = str(body, "Classification");
    r.baseUrl = str(body, "BaseUrl");
    r.healthPath = str(body, "HealthPath");
    return r;
  }

  private static UpdateServiceRequest toUpdateRequest(Json body) {
    UpdateServiceRequest r;
    foreach (key; ["ID", "Name", "Classification", "Status", "Health"])
      if (key in body && key != "ID")
        throw new ValidationException("Property '" ~ key ~ "' cannot be changed");
    if ("Description" in body)
      r.description = str(body, "Description");
    if ("BaseUrl" in body)
      r.baseUrl = str(body, "BaseUrl");
    if ("HealthPath" in body)
      r.healthPath = str(body, "HealthPath");
    return r;
  }

  private static string str(Json body, string key) {
    if (auto v = key in body) {
      if (v.type == Json.Type.string)
        return v.get!string;
      if (v.type == Json.Type.null_)
        return "";
      throw new ValidationException("Property '" ~ key ~ "' must be a string");
    }
    return "";
  }

  private static Json readBody(HTTPServerRequest req) {
    auto body = req.json;
    if (body.type == Json.Type.undefined)
      return Json.emptyObject;
    if (body.type != Json.Type.object)
      throw new ValidationException("Request body must be a JSON object");
    return body;
  }

  private static string[string] queryParams(HTTPServerRequest req) {
    string[string] result;
    foreach (key, value; req.query.byKeyValue)
      result[key] = value;
    return result;
  }

  private void writeEntity(HTTPServerResponse res, int status, string set, Json entity, bool singleton = false) {
    entity["@odata.context"] = singleton ? "$metadata#" ~ set : "$metadata#" ~ set ~ "/$entity";
    writeOData(res, status, entity);
  }

  private static void writeOData(HTTPServerResponse res, int status, Json body) {
    res.headers["OData-Version"] = "4.0";
    res.writeBody(body.toString, status, "application/json;odata.metadata=minimal");
  }

  private static string errorCode(int status) {
    switch (status) {
    case 400:
      return "BadRequest";
    case 403:
      return "PolicyViolation";
    case 404:
      return "NotFound";
    case 405:
      return "MethodNotAllowed";
    case 409:
      return "Conflict";
    case 422:
      return "IntegrityViolation";
    default:
      return "Error";
    }
  }
}

///
unittest {
  auto p = parseResourcePath("/Services('a''b')");
  assert(p.name == "Services" && p.key == "a'b" && p.hasKey);
  assert(parseResourcePath("Transfers/$count").countOnly);
  assert(parseResourcePath("Services(ID='x')").key == "x");
  assert(buildMetadata().indexOf(`<Singleton Name="Overview"`) > 0);
}
