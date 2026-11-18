/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// General HTTP adapters: security headers, authorization guard, health and
/// info endpoints, error rendering.
module neko.platform.presentation.http;

import std.algorithm : among, startsWith;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.common : HTTPMethod;
import vibe.data.json;
import neko.platform.domain;
import neko.platform.infrastructure;

@safe:

/// The caller of a request (bearer token or X-User-Id header).
RequestIdentity identityOf(scope HTTPServerRequest req) {
  return resolveIdentity(req.headers.get("Authorization", ""), req.headers.get("X-User-Id", ""));
}

/// For vibe.web `@before!actorOf("actor")`.
string actorOf(scope HTTPServerRequest req, scope HTTPServerResponse res) {
  return identityOf(req).user;
}

/// Write `{"error": {"code", "message"}}` (also the OData error format).
void writeError(scope HTTPServerResponse res, int status, string code, string message) {
  auto body = Json.emptyObject;
  body["error"] = Json(["code": Json(code), "message": Json(message)]);
  res.writeJsonBody(body, status);
}

class SecurityMiddleware {
  private string[] apiPrefixes;
  private bool enforceScopes;
  private string adminScope;

  this(const PlatformConfig config) {
    apiPrefixes = [config.restPath, config.odataPath, "/api/"];
    enforceScopes = config.enforceScopes;
    adminScope = config.adminScope;
  }

  void registerRoutes(URLRouter router) {
    router.any("*", &handle);
  }

  bool isApi(string path) const {
    foreach (prefix; apiPrefixes)
      if (path.startsWith(prefix))
        return true;
    return false;
  }

  /// Sets headers; rejects modifying API calls without admin scope (if enforced).
  /// Not writing a response lets the router continue with the next handler.
  void handle(HTTPServerRequest req, HTTPServerResponse res) {
    auto api = isApi(req.requestPath.toString);
    res.headers["Content-Security-Policy"] = api ? apiContentSecurityPolicy : uiContentSecurityPolicy;
    res.headers["X-Content-Type-Options"] = "nosniff";
    res.headers["X-Frame-Options"] = "DENY";
    res.headers["Referrer-Policy"] = "no-referrer";
    if (api)
      res.headers["Cache-Control"] = "no-store";

    if (api && enforceScopes && !req.method.among(HTTPMethod.GET, HTTPMethod.HEAD, HTTPMethod.OPTIONS)) {
      auto identity = identityOf(req);
      if (!identity.hasScope(adminScope))
        writeError(res, 403, "Forbidden", "The " ~ adminScope ~ " scope is required for this operation");
    }
  }
}

/// GET /health (plain text, for load balancers) and GET /api/v1/info.
class Health_Controller {
  private PlatformConfig config;
  private SecurityDomain domain;

  this(PlatformConfig config, SecurityDomain domain) {
    this.config = config;
    this.domain = domain;
  }

  void registerRoutes(URLRouter router) {
    router.get("/health", &health);
    router.get("/api/v1/info", &info);
  }

  void health(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody("ok " ~ domain.label, "text/plain; charset=utf-8");
  }

  void info(HTTPServerRequest req, HTTPServerResponse res) {
    auto body = config.toJson(domain);
    body["canExport"] = domain.canExport;
    body["canImport"] = domain.canImport;
    res.writeJsonBody(body);
  }
}
