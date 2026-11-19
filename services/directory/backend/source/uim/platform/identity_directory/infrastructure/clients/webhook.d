/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.infrastructure.clients.webhook;

import vibe.core.core : runTask;
import vibe.http.client : requestHTTP;
import vibe.http.common : HTTPMethod;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Messaging adapter: POSTs every domain event as CloudEvents-style JSON to a
/// webhook (SAP Event Mesh REST, Kafka bridge, ...). Fire and forget — delivery
/// failures are logged and never fail the business operation.
class WebhookEventPublisher : IDirectoryEventPublisher {
  protected string url;
  protected string source;

  this(string url, string source = "/uim/identity-directory") {
    this.url = url;
    this.source = source;
  }

  void publish(string topic, Json payload) {
    auto event = Json.emptyObject
      .set("specversion", "1.0")
      .set("type", topic)
      .set("source", source)
      .set("id", randomUUID().toString)
      .set("time", isoText(nowStdTime()))
      .set("datacontenttype", "application/json");
    event["data"] = payload;
    auto target = url;
    runTask((string target, Json event) nothrow {
      try {
        requestHTTP(target, (scope req) {
          req.method = HTTPMethod.POST;
          req.writeJsonBody(event);
        }, (scope res) {
          if (res.statusCode >= 300)
            logWarn("identity-directory: webhook %s answered %d", target, res.statusCode);
        });
      } catch (Exception e) {
        logWarn("identity-directory: webhook %s failed: %s", target, e.msg);
      }
    }, target, event);
  }
}
