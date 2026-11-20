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
///   errors     error pages (403 for missing rights, 404, …)
///   support    htmx response conventions
///   icons      Tabler icons as inline SVG
///   assets     /ui/* (Tabler, htmx, app.css, theme.js, app.js — embedded)
///   frontend   the Fiori app (catch-all, register last)
module neko.platform.presentation.web;

public:
  import neko.platform.presentation.web.assets;
  import neko.platform.presentation.web.auth;
  import neko.platform.presentation.web.errors;
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

/// Registers the page web interfaces (and the embedded assets) on `router`.
void registerWebPages(URLRouter router, AuthWeb auth, StatusWeb status, UsersWeb users, RolesWeb roles) @safe {
  new AssetsController().registerRoutes(router);
  router.registerWebInterface(auth);
  router.registerWebInterface(status);
  router.registerWebInterface(users);
  router.registerWebInterface(roles);
}
