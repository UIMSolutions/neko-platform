/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// HTTP client adapter for the health gateway port.
module neko.platform.infrastructure.clients.healthgateway;

import core.time : seconds;
import vibe.core.log : logDebug;
import vibe.http.client;
import neko.platform.domain.enumerations : HealthState;
import neko.platform.ports.gateways;

@safe:

/// GET <healthUrl>; any status below 400 counts as up.
class HttpHealthGateway : IServiceHealthGateway {
  private HTTPClientSettings settings;

  this(int timeoutSeconds) {
    settings = new HTTPClientSettings;
    settings.connectTimeout = timeoutSeconds.seconds;
    settings.readTimeout = timeoutSeconds.seconds;
  }

  HealthState probe(string url) {
    try {
      auto state = HealthState.down;
      requestHTTP(url, (scope HTTPClientRequest req) {
        req.method = HTTPMethod.GET;
      }, (scope HTTPClientResponse res) {
        state = res.statusCode < 400 ? HealthState.up : HealthState.down;
        res.dropBody();
      }, settings);
      return state;
    } catch (Exception e) {
      logDebug("health probe %s failed: %s", url, e.msg);
      return HealthState.down;
    }
  }
}
