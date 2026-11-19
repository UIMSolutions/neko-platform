/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// GET /status — the server-rendered status page (signed-in users), and
/// GET /status/live — its live part, polled by htmx every 30 seconds.
/// Works without UI5, which matters in isolated domains.
module neko.platform.presentation.web.status;

import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, render;
import neko.platform.application.dtos;
import neko.platform.ports;
import neko.platform.infrastructure.logging : LoggingEventPublisher;
import neko.platform.presentation.web.guard;

@safe:

class StatusPageController {
  private WebGuard guard;
  private IPlatformOverviewUseCase overview;
  private IManageServicesUseCase services;
  private LoggingEventPublisher events;

  this(WebGuard guard, IPlatformOverviewUseCase overview, IManageServicesUseCase services,
      LoggingEventPublisher events) {
    this.guard = guard;
    this.overview = overview;
    this.services = services;
    this.events = events;
  }

  void registerRoutes(URLRouter router) {
    router.get("/status", &page);
    router.get("/status/live", &live);
  }

  void page(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "Status", "status", false, page))
      return;
    auto info = overview.overview();
    auto catalogue = services.list(ServiceQuery.init);
    auto recent = events.recent();
    res.render!("status.dt", page, info, catalogue, recent);
  }

  void live(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "Status", "status", false, page))
      return;
    auto info = overview.overview();
    auto catalogue = services.list(ServiceQuery.init);
    auto recent = events.recent();
    res.render!("status_live.dt", page, info, catalogue, recent);
  }
}
