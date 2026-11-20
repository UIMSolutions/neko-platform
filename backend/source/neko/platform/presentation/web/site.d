/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The public site: what visitors see, without signing in.
///
///   GET /                          home page of the site for the Host header
///                                  (else the default site); ?lang=de picks a
///                                  language, otherwise Accept-Language decides.
///                                  ?site=<key> previews another site (signed-in
///                                  users with sites.read on that site).
///   GET /media/:site/:id[/:name]   a public file of the site
module neko.platform.presentation.web.site;

import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, render;
import vibe.http.common : HTTPStatusException;
import neko.platform.application.dtos : FileContent, SitePageDto;
import neko.platform.domain : NotFoundException;
import neko.platform.domain.enumerations.rights : AccessRight;
import neko.platform.ports.usecases : IManageFilesUseCase, IManageSitesUseCase;
import neko.platform.presentation.web.files : sendStoredFile;
import neko.platform.presentation.web.guard;

@safe:

class PublicSiteController {
  private WebGuard guard;
  private IManageSitesUseCase sites;
  private IManageFilesUseCase files;

  this(WebGuard guard, IManageSitesUseCase sites, IManageFilesUseCase files) {
    this.guard = guard;
    this.sites = sites;
    this.files = files;
  }

  void registerRoutes(URLRouter router) {
    router.get("/", &home);
    router.get("/media/:site/:id", &media);
    router.get("/media/:site/:id/:name", &media);
  }

  void home(HTTPServerRequest req, HTTPServerResponse res) {
    auto lang = req.query.get("lang", "");
    auto accept = req.headers.get("Accept-Language", "");
    PageContext visitor;
    auto signedIn = guard.tryCurrent(req, visitor);
    SitePageDto view;
    string preview; // set only when a preview is actually shown
    try {
      auto wanted = req.query.get("site", "");
      if (wanted.length && signedIn && visitor.can(AccessRight.sitesRead)) {
        auto site = sites.get(wanted, visitor.user.userName); // 404 outside the user's sites
        view = sites.pageOf(site.key, lang, accept);
        preview = site.key;
      } else
        view = sites.page(req.host, lang, accept);
    } catch (NotFoundException e)
      throw new HTTPStatusException(404, e.msg);

    res.headers["Content-Language"] = view.language;
    res.headers["Vary"] = "Host, Accept-Language, Cookie";
    res.headers["Cache-Control"] = signedIn ? "private, no-cache" : "public, max-age=60";
    render!("site.dt", view, signedIn, visitor, preview)(res);
  }

  void media(HTTPServerRequest req, HTTPServerResponse res) {
    FileContent content;
    if (!files.tryOpenPublic(req.params["site"], req.params["id"], content))
      return; // 404
    sendStoredFile(req, res, content, true, true);
  }
}
