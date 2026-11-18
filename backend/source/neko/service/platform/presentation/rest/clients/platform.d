/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Typed client for a (remote or local) platform instance, built on
/// vibe.d's RestInterfaceClient. Errors arrive as vibe.web.rest.RestException
/// carrying the HTTP status of the business error.
///
///   auto client = new PlatformRestClient("http://127.0.0.1:8080/rest/v1/");
///   client.userId = "alice";
///   auto svc = client.services.postService(RegisterServiceRequest("billing"));
///
///   auto local = PlatformRestClient.overUnixSocket("/tmp/neko-platform-secret.sock");
module neko.platform.presentation.rest.clients.platform;

import vibe.http.client : HTTPClientRequest;
import vibe.inet.url : URL;
import vibe.textfilter.urlencode : urlEncode;
import vibe.web.rest : RestInterfaceClient, RestInterfaceSettings;
import neko.platform.presentation.rest.interfaces;

@safe:

class PlatformRestClient {
  private RestInterfaceClient!IOverviewApi _overview;
  private RestInterfaceClient!IServicesApi _services;
  private RestInterfaceClient!ITransfersApi _transfers;

  /// Sent as X-User-Id (the acting user, recorded in the audit trail).
  string userId;
  /// Sent as "Authorization: Bearer <token>" (XSUAA scopes, if enforced).
  string bearerToken;

  /// `baseUrl` includes the REST path, e.g. "http://host:8080/rest/v1/".
  this(string baseUrl) {
    this(URL(baseUrl));
  }

  this(URL baseUrl) {
    auto settings = new RestInterfaceSettings;
    settings.baseURL = baseUrl;
    _overview = new RestInterfaceClient!IOverviewApi(settings);
    _services = new RestInterfaceClient!IServicesApi(settings);
    _transfers = new RestInterfaceClient!ITransfersApi(settings);
    _overview.requestFilter = &addIdentity;
    _services.requestFilter = &addIdentity;
    _transfers.requestFilter = &addIdentity;
  }

  /// A client for an instance served with transport "unix".
  static PlatformRestClient overUnixSocket(string socketPath, string restPath = "/rest/v1/") {
    return new PlatformRestClient("http+unix://" ~ urlEncode(socketPath) ~ restPath);
  }

  IOverviewApi overview() { return _overview; }
  IServicesApi services() { return _services; }
  ITransfersApi transfers() { return _transfers; }

  private void addIdentity(HTTPClientRequest req) {
    if (userId.length > 0)
      req.headers["X-User-Id"] = userId;
    if (bearerToken.length > 0)
      req.headers["Authorization"] = "Bearer " ~ bearerToken;
  }
}
