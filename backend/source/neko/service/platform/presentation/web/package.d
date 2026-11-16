/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web adapters: a server-rendered status page (Diet, daisyUI class names)
/// and the SAP Fiori app served from frontend/ for local development.
module neko.service.platform.presentation.web;

import std.file : exists, isDir;
import std.path : buildPath, dirName;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, render;
import neko.service.platform.domain;
import neko.service.platform.application.dtos;
import neko.service.platform.ports;
import neko.service.platform.infrastructure.logging : LoggingEventPublisher;

@safe:

/// GET /status — works without JavaScript and without UI5 (useful in
/// isolated domains and for operators).
class StatusPageController {
  private IPlatformOverviewUseCase overview;
  private IManageServicesUseCase services;
  private LoggingEventPublisher events;
  private string serviceName;

  this(IPlatformOverviewUseCase overview, IManageServicesUseCase services, LoggingEventPublisher events,
      string serviceName) {
    this.overview = overview;
    this.services = services;
    this.events = events;
    this.serviceName = serviceName;
  }

  void registerRoutes(URLRouter router) {
    router.get("/status", &page);
  }

  void page(HTTPServerRequest req, HTTPServerResponse res) {
    auto info = overview.overview();
    auto catalogue = services.list(ServiceQuery.init);
    auto recent = events.recent();
    auto title = serviceName;
    res.render!("status.dt", title, info, catalogue, recent);
  }
}

/// Serves the UI5 app at "/". Register LAST: it is a catch-all for GET.
/// The UI5 manifest uses relative URIs, so the same files work behind the approuter.
class FrontendController {
  private string directory;

  /// `configured` = "" → first of frontend/dist (self-contained build incl. UI5),
  /// frontend/, ../frontend/dist, ../frontend, <exe>/../../frontend[/dist] that has an index.html
  this(string configured) {
    directory = configured.length > 0 ? configured : detect();
  }

  string location() const {
    return directory;
  }

  bool available() const {
    return directory.length > 0 && (() @trusted => directory.exists && directory.isDir
        && buildPath(directory, "index.html").exists)();
  }

  void registerRoutes(URLRouter router) {
    if (available)
      router.get("*", serveStaticFiles(directory));
  }

  private static string detect() {
    string[] roots = [".", ".."];
    try {
      import std.file : thisExePath;

      roots ~= buildPath((() @trusted => thisExePath.dirName)(), "..", "..");
    } catch (Exception) {
    }
    string[] candidates;
    foreach (root; roots)
      candidates ~= [buildPath(root, "frontend", "dist"), buildPath(root, "frontend")];
    foreach (c; candidates)
      if ((() @trusted => buildPath(c, "index.html").exists)())
        return c;
    return "";
  }
}
