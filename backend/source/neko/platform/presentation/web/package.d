/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web adapters: server-rendered pages (Diet templates, Beer CSS, htmx) with
/// sign-in and user management, plus the SAP Fiori app for local development.
///
///   guard      PageContext, WebGuard (session → signed-in user, CSRF)
///   sessions   WebSessions, LoginThrottle, origin checks
///   auth       /login, /logout, /account
///   users      /users (administrators)
///   status     /status, /status/live
///   assets     /ui/* (Beer CSS, htmx, icon font, app.css, app.js — embedded)
///   frontend   the Fiori app (catch-all, register last)
module neko.platform.presentation.web;

public:
  import neko.platform.presentation.web.assets;
  import neko.platform.presentation.web.auth;
  import neko.platform.presentation.web.frontend;
  import neko.platform.presentation.web.guard;
  import neko.platform.presentation.web.sessions;
  import neko.platform.presentation.web.status;
  import neko.platform.presentation.web.users;
