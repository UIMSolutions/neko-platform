/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// What needs no sign-in:
///
///   GET /                                to the pages: /start when signed in,
///                                        else /login
///   GET /media/:subaccount/:id[/:name]   a public file of a subaccount
module neko.platform.presentation.web.home;

import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import neko.platform.application.dtos : FileContent;
import neko.platform.ports.usecases : IManageFilesUseCase;
import neko.platform.presentation.web.files : sendStoredFile;
import neko.platform.presentation.web.guard;

@safe:

class HomeController {
  private WebGuard guard;
  private IManageFilesUseCase files;

  this(WebGuard guard, IManageFilesUseCase files) {
    this.guard = guard;
    this.files = files;
  }

  void registerRoutes(URLRouter router) {
    router.get("/", &home);
    router.get("/media/:subaccount/:id", &media);
    router.get("/media/:subaccount/:id/:name", &media);
  }

  void home(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext visitor;
    res.headers["Cache-Control"] = "no-store";
    res.redirect(guard.tryCurrent(req, visitor) ? "/start" : "/login", 303);
  }

  void media(HTTPServerRequest req, HTTPServerResponse res) {
    FileContent content;
    if (!files.tryOpenPublic(req.params["subaccount"], req.params["id"], content))
      return; // 404
    sendStoredFile(req, res, content, true, true);
  }
}
