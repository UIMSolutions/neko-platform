/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The account model at the HTTP level:
///
///   GlobalAccountDispatcher   picks the global account of a request (host
///                             name, else X-Neko-Global-Account, else the
///                             default one) and hands the request to that
///                             global account's own router
///   CallContextMiddleware     resolves the tenant and space of a service
///                             call (X-Neko-Subaccount, X-Neko-Tenant,
///                             X-Neko-Space, the host name) and echoes them
///                             as response headers, with the region the
///                             subaccount runs in (X-Neko-Region: the
///                             secondary one after a failover)
///   GET <restPath>context     the call context of the request
module neko.platform.presentation.http.accounts;

import std.algorithm : startsWith;
import vibe.data.json : Json, serializeToJson;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse;
import neko.platform.domain : CallContext, CallRequest, NotFoundException, PlatformException;
import neko.platform.domain.types.host : normalizeHost;
import neko.platform.ports.usecases : IManageGlobalAccountsUseCase, IManageLandscapeUseCase;

@safe:

enum globalAccountHeader = "X-Neko-Global-Account";
enum subaccountHeader = "X-Neko-Subaccount";
enum tenantHeader = "X-Neko-Tenant";
enum spaceHeader = "X-Neko-Space";
/// Response only: the region serving the subaccount.
enum regionHeader = "X-Neko-Region";

/// A string kept in the request context ("" if absent).
string contextValue(scope HTTPServerRequest req, string key) @trusted {
  if (auto v = key in req.context)
    if (v.convertsTo!string)
      return v.get!string;
  return "";
}

void setContextValue(scope HTTPServerRequest req, string key, string value) @trusted {
  req.context[key] = value;
}

/// The call context the middleware stored (empty fields if none).
CallContext callContextOf(scope HTTPServerRequest req) {
  CallContext c;
  c.globalAccount = req.contextValue("neko.globalAccount");
  c.subaccount = req.contextValue("neko.subaccount");
  c.subdomain = req.contextValue("neko.subdomain");
  c.tenant = req.contextValue("neko.tenant");
  c.space = req.contextValue("neko.space");
  c.region = req.contextValue("neko.region");
  c.source = req.contextValue("neko.callSource");
  return c;
}

class GlobalAccountDispatcher : HTTPServerRequestHandler {
  private IManageGlobalAccountsUseCase accounts;
  private HTTPServerRequestHandler delegate(string key) @safe handlerOf;

  /// `handlerOf` gives the handler (router) of a global account.
  this(IManageGlobalAccountsUseCase accounts, HTTPServerRequestHandler delegate(string key) @safe handlerOf) {
    this.accounts = accounts;
    this.handlerOf = handlerOf;
  }

  void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    string key;
    try
      key = accounts.resolve(req.host, req.headers.get(globalAccountHeader, "")).key;
    catch (NotFoundException e) {
      res.writeBody(e.msg, 404, "text/plain; charset=utf-8");
      return;
    }
    req.setContextValue("neko.globalAccount", key);
    res.headers[globalAccountHeader] = key;
    handlerOf(key).handleRequest(req, res);
  }
}

class CallContextMiddleware {
  private IManageLandscapeUseCase landscape;
  private string globalAccount;
  private string restPath, odataPath;

  this(IManageLandscapeUseCase landscape, string globalAccount, string restPath, string odataPath) {
    this.landscape = landscape;
    this.globalAccount = globalAccount;
    this.restPath = restPath;
    this.odataPath = odataPath;
  }

  /// Register first: it only annotates the request (or refuses it).
  void registerRoutes(URLRouter router) {
    router.any("*", &resolve);
    router.get(restPath ~ "context", &show);
  }

  void resolve(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    auto path = req.requestPath.toString;
    if (path.startsWith("/ui/") || path == "/health" || path == "/metrics")
      return;
    auto r = CallRequest(normalizeHost(req.host), req.headers.get(subaccountHeader, ""),
      req.headers.get(tenantHeader, ""), req.headers.get(spaceHeader, ""));
    auto named = r.subaccount.length || r.tenant.length || r.space.length;
    auto api = path.startsWith(restPath) || path.startsWith(odataPath);
    try {
      auto c = landscape.resolveCall(r);
      req.setContextValue("neko.subaccount", c.subaccount);
      req.setContextValue("neko.subdomain", c.subdomain);
      req.setContextValue("neko.tenant", c.tenant);
      req.setContextValue("neko.space", c.space);
      req.setContextValue("neko.region", c.region);
      req.setContextValue("neko.callSource", c.source);
      res.headers[subaccountHeader] = c.subaccount;
      res.headers[tenantHeader] = c.tenant;
      res.headers[spaceHeader] = c.space;
      res.headers[regionHeader] = c.region;
    } catch (PlatformException e) {
      // A tenant or space that was asked for and does not exist: refused.
      // Pages without such a request go on without a call context.
      if (!named && !api)
        return;
      auto body = Json.emptyObject;
      body["error"] = Json(["code": Json(e.code == 404 ? "NotFound" : "BadRequest"), "message": Json(e.msg)]);
      res.writeJsonBody(body, e.code == 404 ? 404 : 400);
    }
  }

  /// GET <restPath>context
  void show(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    auto c = callContextOf(req);
    if (c.globalAccount.length == 0)
      c.globalAccount = globalAccount;
    res.headers["Cache-Control"] = "no-store";
    res.writeJsonBody(serializeToJson(c));
  }
}
