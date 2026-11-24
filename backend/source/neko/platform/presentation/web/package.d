/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web adapters: server-rendered pages — vibe.d web interfaces (vibe.web.web,
/// access rights via vibe.web.auth), Diet templates, Tabler and htmx — plus
/// the SAP Fiori app for local development.
///
///   guard      PageContext (auth info, one predicate per access right), WebGuard, PageAuthentication
///   sessions   WebSessions, LoginThrottle, origin checks
///   auth       /login, /logout, /start, /account                      (AuthWeb)
///   status     /status, /status/live                                  (StatusWeb, status.read)
///   users      /users                                                 (UsersWeb, users.read / users.manage)
///   roles      /roles                                                 (RolesWeb, roles.read / roles.manage)
///   files      /files: the libraries of the subaccounts               (FilesWeb, files.read / files.manage)
///   landscape  /landscape: global account, directories, subaccounts, tenants, spaces, billing,
///              service assignments, disaster recovery                 (LandscapeWeb)
///   accounts   /accounts: the global accounts of the instance, default one only  (GlobalAccountsWeb, accounts.manage)
///   security   /security: firewall, traffic, IP lists, bans            (SecurityWeb, security.read / security.manage)
///   monitoring /monitoring                                            (MonitoringWeb, monitoring.read)
///   home       / (to the pages), /media/*: public files              (HomeController, no sign-in)
///   errors     error pages (403 for missing rights, 404, …)
///   support    htmx response conventions
///   icons      Tabler icons as inline SVG
///   assets     /ui/* (Tabler, htmx, app.css, theme.js, app.js — embedded)
///   frontend   the Fiori app (catch-all, register last)
module neko.platform.presentation.web;

public:
  import neko.platform.presentation.web.accounts;
  import neko.platform.presentation.web.assets;
  import neko.platform.presentation.web.auth;
  import neko.platform.presentation.web.errors;
  import neko.platform.presentation.web.files;
  import neko.platform.presentation.web.monitoring;
  import neko.platform.presentation.web.security;
  import neko.platform.presentation.web.landscape;
  import neko.platform.presentation.web.home;
  import neko.platform.presentation.web.frontend;
  import neko.platform.presentation.web.guard;
  import neko.platform.presentation.web.icons;
  import neko.platform.presentation.web.roles;
  import neko.platform.presentation.web.sessions;
  import neko.platform.presentation.web.status;
  import neko.platform.presentation.web.support;
  import neko.platform.presentation.web.users;

import vibe.http.router : URLRouter;
import vibe.web.web : registerWebInterface;
import neko.platform.presentation.web.auth : AuthWeb;
import neko.platform.presentation.web.roles : RolesWeb;
import neko.platform.presentation.web.status : StatusWeb;
import neko.platform.presentation.web.users : UsersWeb;
import neko.platform.presentation.web.files : FilesWeb;
import neko.platform.presentation.web.monitoring : MonitoringWeb;
import neko.platform.presentation.web.security : SecurityWeb;
import neko.platform.presentation.web.landscape : LandscapeWeb;
import neko.platform.presentation.web.home : HomeController;
import neko.platform.presentation.web.accounts : GlobalAccountsWeb;

/// The page controllers.
struct WebPages {
  AuthWeb auth;
  StatusWeb status;
  MonitoringWeb monitoring;
  SecurityWeb security;
  LandscapeWeb landscape;
  FilesWeb files;
  UsersWeb users;
  RolesWeb roles;
  HomeController home;
  /// Only in the default global account; may be null.
  GlobalAccountsWeb accounts;
}

/// Registers "/", the public files, the page web interfaces and the embedded assets on `router`.
void registerWebPages(URLRouter router, WebPages pages) @safe {
  new AssetsController().registerRoutes(router);
  pages.home.registerRoutes(router);
  router.registerWebInterface(pages.auth);
  router.registerWebInterface(pages.status);
  router.registerWebInterface(pages.monitoring);
  router.registerWebInterface(pages.security);
  router.registerWebInterface(pages.landscape);
  router.registerWebInterface(pages.files);
  router.registerWebInterface(pages.users);
  router.registerWebInterface(pages.roles);
  if (pages.accounts !is null)
    router.registerWebInterface(pages.accounts);
}
