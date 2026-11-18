/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Round trip: PlatformRestClient → HTTP → REST services → use cases (memory store).
module neko.platform.presentation.rest.tests.roundtrip;

version (unittest):

import std.format : format;
import vibe.core.core : runTask;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerSettings, listenHTTP;
import vibe.web.rest : RestException;
import neko.platform.application.dtos;
import neko.platform.domain : SecurityDomain;
import neko.platform.infrastructure.configuration : PlatformConfig;
import neko.platform.infrastructure.container : buildContainer;
import neko.platform.presentation.rest.clients;
import neko.platform.presentation.rest.services : registerPlatformRestApi;

unittest {
  PlatformConfig config;
  config.storage = "memory";
  auto c = buildContainer(config, SecurityDomain.open);

  auto router = new URLRouter;
  router.registerPlatformRestApi(c.services, c.health, c.transfers, c.overview, "/rest/v1/");
  auto settings = new HTTPServerSettings;
  settings.port = 0;
  settings.bindAddresses = ["127.0.0.1"];
  auto listener = listenHTTP(settings, router);
  scope (exit)
    listener.stopListening();

  string failure;
  runTask(() nothrow {
    try {
      auto client = new PlatformRestClient(format("http://127.0.0.1:%d/rest/v1/", listener.bindAddresses[0].port));
      client.userId = "alice";

      auto created = client.services.postService(RegisterServiceRequest("billing", "Billing service"));
      assert(created.id.length > 0 && created.name == "billing");
      assert(client.services.getService(created.id).description == "Billing service");
      assert(client.services.getServices("bill").length == 1);
      assert(client.services.postActivate(created.id).status == "active");

      int status;
      try
        client.services.getService("does-not-exist");
      catch (RestException e)
        status = e.status;
      assert(status == 404, format("expected 404, got %s", status));

      assert(client.transfers.getTransfers().length == 0);
      assert(client.overview.getOverview() != OverviewDto.init);
    } catch (Throwable t)
      failure = t.msg;
  }).join();
  assert(failure.length == 0, "REST round trip failed: " ~ failure);
}
