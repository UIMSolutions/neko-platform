/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The server-rendered status page (web interface). Works without UI5, which
/// matters in isolated domains.
///
///   GET /status        page                      status.read
///   GET /status/live   its live part, polled by htmx every 30 seconds
///
/// Recent events are only listed with the right events.read.
module neko.platform.presentation.web.status;

import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos;
import neko.platform.domain.enumerations.rights : AccessRight;
import neko.platform.ports.messaging : PlatformEvent;
import neko.platform.ports.usecases : IManageServicesUseCase, IPlatformOverviewUseCase;
import neko.platform.infrastructure.logging : LoggingEventPublisher;
import neko.platform.presentation.web.guard;

@safe:

@requiresAuth
class StatusWeb {
  private WebGuard guard;
  private IPlatformOverviewUseCase overview;
  private IManageServicesUseCase services;
  private LoggingEventPublisher events;

  mixin PageAuthentication;

  this(WebGuard guard, IPlatformOverviewUseCase overview, IManageServicesUseCase services,
      LoggingEventPublisher events) {
    this.guard = guard;
    this.overview = overview;
    this.services = services;
    this.events = events;
  }

  @auth(Role.statusRead) @path("/status")
  void getStatus(PageContext page) {
    page = page.at("Status", "status");
    auto info = overview.overview();
    auto catalogue = services.list(ServiceQuery.init);
    auto recent = recentEvents(page);
    render!("status.dt", page, info, catalogue, recent);
  }

  @auth(Role.statusRead) @path("/status/live")
  void getStatusLive(PageContext page) {
    page = page.at("Status", "status");
    auto info = overview.overview();
    auto catalogue = services.list(ServiceQuery.init);
    auto recent = recentEvents(page);
    render!("status_live.dt", page, info, catalogue, recent);
  }

  private PlatformEvent[] recentEvents(const PageContext page) {
    return page.can(AccessRight.eventsRead) ? events.recent() : null;
  }
}
