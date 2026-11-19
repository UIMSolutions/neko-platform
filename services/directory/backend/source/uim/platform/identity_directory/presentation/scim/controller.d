/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// SCIM 2.0 service provider (RFC 7644) on top of the resource registry, for
/// provisioning clients such as SAP Cloud Identity Services, Azure AD / Entra ID and Okta.
///
///   GET/POST          <base>/Users            ?filter=&startIndex=&count=&sortBy=&sortOrder=&attributes=&excludedAttributes=
///   GET/PUT/PATCH/DEL <base>/Users/<id>
///   GET/POST          <base>/Groups · GET/PUT/PATCH/DEL <base>/Groups/<id>
///   POST              <base>/Users/.search · <base>/Groups/.search
///   GET               <base>/Schemas[/<urn>] · <base>/ResourceTypes[/<name>] · <base>/ServiceProviderConfig
///
/// Media type application/scim+json; errors use the SCIM error schema.
module neko.directory.presentation.scim.controller;

import std.uni : icmp;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.stream.operations : readAllUTF8;
import neko.directory;
import neko.directory.presentation.resources;
import neko.directory.presentation.scim.mapping;

mixin(ShowModule!());

@safe:

/// Largest page a list request returns.
enum int scimMaxResults = 200;

/// SCIM query parameters of a list / search request.
struct ScimQuery {
  string filter;
  int startIndex = 1;
  int count = 100;
  string sortBy;
  bool descending;
  string[] attributes;
  string[] excludedAttributes;

  static ScimQuery of(scope string delegate(string) @safe get) {
    ScimQuery q;
    q.filter = get("filter");
    q.sortBy = get("sortBy");
    q.descending = get("sortOrder").toLower == "descending";
    try {
      if (get("startIndex").length)
        q.startIndex = max(1, get("startIndex").to!int);
      if (get("count").length)
        q.count = min(scimMaxResults, max(0, get("count").to!int));
    } catch (Exception)
      throw new ResourceError(400, "invalidValue", "startIndex and count must be integers");
    q.attributes = jsonStrings(Json(get("attributes")));
    q.excludedAttributes = jsonStrings(Json(get("excludedAttributes")));
    return q;
  }
}

/// Filter, sort, page and project SCIM resources; returns a ListResponse.
Json scimList(Json[] resources, const ScimQuery q) {
  if (q.filter.length > 0) {
    ScimFilter filter;
    try
      filter = parseScimFilter(q.filter);
    catch (DirectoryValidationException e)
      throw new ResourceError(400, "invalidFilter", e.msg);
    resources = resources.filter!(r => filter.matches(r)).array;
  }
  if (q.sortBy.length > 0) {
    string sortKey(Json r) {
      auto v = resolve(r, q.sortBy);
      return v.length ? jsonText(v[0]).toLower : "";
    }

    resources.sort!((a, b) => q.descending ? sortKey(a) > sortKey(b) : sortKey(a) < sortKey(b));
  }
  auto total = resources.length;
  auto from = min(total, cast(size_t) q.startIndex - 1);
  auto page = resources[from .. min(total, from + q.count)];
  auto items = Json.emptyArray;
  foreach (r; page)
    items ~= project(r, q.attributes, q.excludedAttributes);
  return Json.emptyObject
    .set("schemas", Json([Json(scimListSchema)]))
    .set("totalResults", total)
    .set("startIndex", q.startIndex)
    .set("itemsPerPage", page.length)
    .set("Resources", items);
}

/// Keep `attributes` (plus id, schemas, meta) or drop `excluded` top-level attributes.
Json project(Json resource, const string[] attributes, const string[] excluded) {
  if (attributes.length == 0 && excluded.length == 0)
    return resource;
  auto result = Json.emptyObject;
  foreach (k, v; resource.get!(Json[string])) {
    bool always = ["id", "schemas", "meta"].canFind(k);
    bool wanted = attributes.length == 0 || attributes.any!(a => icmp(a.split(".")[0], k) == 0);
    bool dropped = excluded.any!(a => icmp(a, k) == 0);
    if (always || (wanted && !dropped))
      result[k] = v;
  }
  return result;
}

class ScimController {
  protected ResourceRegistry registry;
  protected string basePath;
  protected string defaultTenant;

  this(ResourceRegistry registry, string basePath, string defaultTenant) {
    this.registry = registry;
    this.basePath = basePath.stripRight("/");
    this.defaultTenant = defaultTenant;
  }

  void registerRoutes(URLRouter router) {
    auto b = basePath;
    router.get(b ~ "/ServiceProviderConfig", (req, res) => guard(res, () => write(res, 200, serviceProviderConfig())));
    router.get(b ~ "/ResourceTypes", (req, res) => guard(res, () => write(res, 200, listOf(resourceTypes(identityOf(req))))));
    router.get(b ~ "/ResourceTypes/:name", (req, res) => guard(res, () {
      foreach (t; resourceTypes(identityOf(req)))
        if (t["id"].get!string == req.params["name"])
          return write(res, 200, t);
      throw new ResourceError(404, "", "Resource type '" ~ req.params["name"] ~ "' not found");
    }));
    router.get(b ~ "/Schemas", (req, res) => guard(res, () => write(res, 200, listOf(schemas(identityOf(req))))));
    router.get(b ~ "/Schemas/:id", (req, res) => guard(res, () {
      foreach (s; schemas(identityOf(req)))
        if (s["id"].get!string == req.params["id"])
          return write(res, 200, s);
      throw new ResourceError(404, "", "Schema '" ~ req.params["id"] ~ "' not found");
    }));
    registerKind(router, "Users", "users");
    registerKind(router, "Groups", "groups");
  }

  protected void registerKind(URLRouter router, string endpoint, string resource) {
    auto base = basePath ~ "/" ~ endpoint;
    auto adapter = registry.byPath(resource);

    router.get(base, (req, res) => guard(res, () {
      auto who = identityOf(req);
      write(res, 200, scimList(all(who, resource), ScimQuery.of((name) => req.query.get(name, ""))));
    }));
    router.post(base ~ "/.search", (req, res) => guard(res, () {
      auto who = identityOf(req);
      auto body = bodyOf(req);
      write(res, 200, scimList(all(who, resource), ScimQuery.of((name) {
        auto v = fieldOf(body, name);
        return v.type == Json.Type.array ? v.get!(Json[]).map!(x => jsonText(x)).join(",") : jsonText(v);
      })));
    }));
    router.post(base, (req, res) => guard(res, () {
      auto who = identityOf(req);
      auto payload = toPayload(resource, bodyOf(req), false);
      auto created = adapter.create(who, registry.withReferences(who.tenantId, payload));
      auto scim = toScim(who, resource, created);
      res.headers["Location"] = scim["meta"]["location"].get!string;
      write(res, 201, scim);
    }));
    router.get(base ~ "/:id", (req, res) => guard(res, () {
      auto who = identityOf(req);
      write(res, 200, toScim(who, resource, require(who, adapter, req.params["id"])));
    }));
    router.put(base ~ "/:id", (req, res) => guard(res, () {
      auto who = identityOf(req);
      require(who, adapter, req.params["id"]);
      auto payload = toPayload(resource, bodyOf(req), true);
      write(res, 200, toScim(who, resource, adapter.update(who, req.params["id"], registry.withReferences(who.tenantId, payload))));
    }));
    router.patch(base ~ "/:id", (req, res) => guard(res, () {
      auto who = identityOf(req);
      auto current = toScim(who, resource, require(who, adapter, req.params["id"]));
      auto patched = applyPatch(current, bodyOf(req));
      auto payload = toPayload(resource, patched, true);
      auto password = fieldOf(patched, "password");
      if (password.type == Json.Type.string)
        payload["password"] = password;
      auto updated = adapter.update(who, req.params["id"], registry.withReferences(who.tenantId, payload));
      write(res, 200, toScim(who, resource, updated));
    }));
    router.delete_(base ~ "/:id", (req, res) => guard(res, () {
      auto who = identityOf(req);
      require(who, adapter, req.params["id"]);
      adapter.remove(who, req.params["id"]);
      res.statusCode = 204;
      res.writeVoidBody();
    }));
  }

  // ── mapping ────────────────────────────────────────────────────────────

  protected SchemaCatalog catalogOf(RequestIdentity who) {
    return SchemaCatalog.of(registry.byPath("schemas").list(who.tenantId));
  }

  protected Json toScim(RequestIdentity who, string resource, Json payload) {
    auto catalog = catalogOf(who);
    if (resource == "groups")
      return groupToScim(payload, basePath, catalog);
    string[string] groupIds;
    foreach (g; registry.byPath("groups").list(who.tenantId))
      groupIds[fieldString(g, "displayName")] = fieldString(g, "id");
    return userToScim(payload, basePath, catalog, groupIds);
  }

  protected Json toPayload(string resource, Json scim, bool full) {
    try
      return resource == "groups" ? scimToGroup(scim, full) : scimToUser(scim, full);
    catch (DirectoryException e)
      throw new ResourceError(400, "invalidSyntax", e.msg);
  }

  protected Json[] all(RequestIdentity who, string resource) {
    auto catalog = catalogOf(who);
    Json[] result;
    if (resource == "groups") {
      foreach (g; registry.byPath("groups").list(who.tenantId))
        result ~= groupToScim(g, basePath, catalog);
      return result;
    }
    string[string] groupIds;
    foreach (g; registry.byPath("groups").list(who.tenantId))
      groupIds[fieldString(g, "displayName")] = fieldString(g, "id");
    foreach (u; registry.byPath("users").list(who.tenantId))
      result ~= userToScim(u, basePath, catalog, groupIds);
    return result;
  }

  protected Json require(RequestIdentity who, IResourceAdapter adapter, string id) {
    auto row = adapter.get(who.tenantId, id);
    if (row.type == Json.Type.null_)
      throw new ResourceError(404, "", "Resource " ~ id ~ " not found");
    return row;
  }

  // ── discovery ──────────────────────────────────────────────────────────

  Json serviceProviderConfig() {
    Json supported(bool on) {
      return Json.emptyObject.set("supported", on);
    }

    auto scheme = Json.emptyObject
      .set("type", "oauthbearertoken")
      .set("name", "OAuth Bearer Token")
      .set("description", "XSUAA / OAuth 2.0 bearer token (RFC 6750)")
      .set("primary", true);
    return Json.emptyObject
      .set("schemas", Json([Json("urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig")]))
      .set("patch", supported(true))
      .set("bulk", supported(false).set("maxOperations", 0).set("maxPayloadSize", 0))
      .set("filter", supported(true).set("maxResults", scimMaxResults))
      .set("changePassword", supported(true))
      .set("sort", supported(true))
      .set("etag", supported(false))
      .set("authenticationSchemes", Json([scheme]))
      .set("meta", Json.emptyObject.set("resourceType", "ServiceProviderConfig").set("location", basePath ~ "/ServiceProviderConfig"));
  }

  Json[] resourceTypes(RequestIdentity who) {
    Json[] result;
    foreach (kind; [["User", "/Users", scimUserSchema, "user", scimDirectoryUserSchema],
        ["Group", "/Groups", scimGroupSchema, "group", scimDirectoryGroupSchema]]) {
      auto extensions = Json([Json.emptyObject.set("schema", kind[4]).set("required", false)]);
      foreach (s; registry.byPath("schemas").list(who.tenantId))
        if (fieldString(s, "target") == kind[3])
          extensions ~= Json.emptyObject.set("schema", fieldString(s, "urn")).set("required", false);
      result ~= Json.emptyObject
        .set("schemas", Json([Json("urn:ietf:params:scim:schemas:core:2.0:ResourceType")]))
        .set("id", kind[0])
        .set("name", kind[0])
        .set("endpoint", kind[1])
        .set("schema", kind[2])
        .set("schemaExtensions", extensions)
        .set("meta", Json.emptyObject.set("resourceType", "ResourceType").set("location", basePath ~ "/ResourceTypes/" ~ kind[0]));
    }
    return result;
  }

  Json[] schemas(RequestIdentity who) {
    Json attr(string name, string type = "string", bool multi = false, bool required = false, string mutability = "readWrite") {
      return Json.emptyObject.set("name", name).set("type", type).set("multiValued", multi).set("required", required)
        .set("caseExact", false).set("mutability", mutability).set("returned", "default").set("uniqueness", name == "userName" ? "server" : "none");
    }

    Json schema(string id, string name, string description, Json[] attributes) {
      return Json.emptyObject
        .set("schemas", Json([Json("urn:ietf:params:scim:schemas:core:2.0:Schema")]))
        .set("id", id).set("name", name).set("description", description)
        .set("attributes", Json(attributes))
        .set("meta", Json.emptyObject.set("resourceType", "Schema").set("location", basePath ~ "/Schemas/" ~ id));
    }

    Json[] result;
    result ~= schema(scimUserSchema, "User", "User Account", [attr("userName", "string", false, true),
      attr("name", "complex"), attr("displayName"), attr("nickName"), attr("profileUrl", "reference"), attr("title"),
      attr("userType"), attr("preferredLanguage"), attr("locale"), attr("timezone"), attr("active", "boolean"),
      attr("password", "string", false, false, "writeOnly"), attr("emails", "complex", true),
      attr("phoneNumbers", "complex", true), attr("addresses", "complex", true),
      attr("groups", "complex", true, false, "readOnly")]);
    result ~= schema(scimGroupSchema, "Group", "Group", [attr("displayName", "string", false, true),
      attr("members", "complex", true)]);
    result ~= schema(scimDirectoryUserSchema, "DirectoryUser", "Directory specific user attributes",
      [attr("status"), attr("passwordPolicy"), attr("mustChangePassword", "boolean", false, false, "readOnly"),
      attr("lastLoginAt", "dateTime", false, false, "readOnly")]);
    result ~= schema(scimDirectoryGroupSchema, "DirectoryGroup", "Directory specific group attributes",
      [attr("description"), attr("groupType"), attr("membershipRule")]);
    foreach (s; registry.byPath("schemas").list(who.tenantId)) {
      Json[] attributes;
      if (member(s, "attributes").type == Json.Type.array)
        foreach (a; s["attributes"].get!(Json[])) {
          auto j = Json.emptyObject;
          foreach (key; ["name", "description", "type", "multiValued", "required", "caseExact", "mutability", "returned", "uniqueness", "canonicalValues"])
            j[key] = member(a, key);
          attributes ~= j;
        }
      result ~= schema(fieldString(s, "urn"), fieldString(s, "name"), fieldString(s, "description"), attributes);
    }
    return result;
  }

  protected static Json listOf(Json[] items) {
    return Json.emptyObject
      .set("schemas", Json([Json(scimListSchema)]))
      .set("totalResults", items.length)
      .set("startIndex", 1)
      .set("itemsPerPage", items.length)
      .set("Resources", Json(items));
  }

  // ── helpers ────────────────────────────────────────────────────────────

  protected RequestIdentity identityOf(HTTPServerRequest req) {
    return resolveIdentity(req.headers.get("Authorization", ""), req.headers.get("X-Tenant-Id", ""),
      req.headers.get("X-User-Id", ""), defaultTenant);
  }

  protected static Json bodyOf(HTTPServerRequest req) {
    Json b;
    try {
      b = req.json;
      if (b.type == Json.Type.undefined) {
        auto text = (() @trusted => req.bodyReader.readAllUTF8())();
        b = text.strip.length ? parseJsonString(text) : Json.emptyObject;
      }
    } catch (Exception e)
      throw new ResourceError(400, "invalidSyntax", "Request body is not valid JSON: " ~ e.msg);
    if (b.type != Json.Type.object)
      throw new ResourceError(400, "invalidSyntax", "Request body must be a JSON object");
    return b;
  }

  protected static void guard(HTTPServerResponse res, scope void delegate() @safe action) {
    try
      action();
    catch (ResourceError e)
      writeError(res, e.status, scimType(e), e.msg);
    catch (DirectoryException e)
      writeError(res, e.status == 422 ? 400 : e.status, e.status == 422 ? "invalidValue" : "", e.msg);
    catch (Exception e) {
      logError("identity-directory scim: %s", e.msg);
      writeError(res, 500, "", e.msg);
    }
  }

  /// SCIM error type of a ResourceError (RFC 7644 table 9).
  protected static string scimType(ResourceError e) {
    switch (e.code) {
    case "invalidFilter", "invalidSyntax", "invalidValue", "invalidPath", "tooMany":
      return e.code;
    case "Conflict":
      return "uniqueness";
    case "BusinessRuleViolation", "InvalidPayload":
      return "invalidValue";
    default:
      return "";
    }
  }

  protected static void write(HTTPServerResponse res, int status, Json payload) {
    res.writeBody(payload.toString, status, "application/scim+json; charset=utf-8");
  }

  protected static void writeError(HTTPServerResponse res, int status, string scimType, string detail) {
    // SCIM has no 422: business rule violations are 400 invalidValue
    if (status == 422) {
      status = 400;
      if (scimType.length == 0)
        scimType = "invalidValue";
    }
    auto err = Json.emptyObject
      .set("schemas", Json([Json(scimErrorSchema)]))
      .set("status", status.to!string)
      .set("detail", detail);
    if (scimType.length)
      err["scimType"] = scimType;
    write(res, status, err);
  }
}

///
unittest {
  mixin(ShowTest!("scimList"));

  Json[] users;
  foreach (name; ["carol", "alice", "bob"])
    users ~= parseJsonString(`{"id": "` ~ name ~ `", "userName": "` ~ name ~ `", "title": "x", "schemas": [], "meta": {}}`);
  ScimQuery q;
  q.sortBy = "userName";
  q.count = 2;
  auto page = scimList(users, q);
  assert(page["totalResults"].get!long == 3 && page["itemsPerPage"].get!long == 2);
  assert(page["Resources"][0]["userName"].get!string == "alice");
  q.filter = `userName sw "b"`;
  q.attributes = ["userName"];
  page = scimList(users, q);
  assert(page["totalResults"].get!long == 1 && "title" !in page["Resources"][0] && "id" in page["Resources"][0]);
  q.filter = `userName zz "b"`;
  int status;
  try scimList(users, q);
  catch (ResourceError e) status = e.status;
  assert(status == 400);
}
