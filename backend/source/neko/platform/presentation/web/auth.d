/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Sign-in, sign-out and the own account (password change).
///
///   GET  /login              sign-in form (?next=<local path>)
///   POST /login              user, password, next
///   POST /logout
///   GET  /account            own account
///   POST /account/password   current, password, confirm (htmx: returns the form)
module neko.platform.presentation.web.auth;

import core.time : Duration;
import std.conv : to;
import std.string : strip, toLower;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, render;
import neko.platform.domain : AuthenticationException, PlatformException;
import neko.platform.ports.usecases : IAuthenticateUseCase, IManageUsersUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.sessions;

@safe:

class AuthController {
  private WebGuard guard;
  private IAuthenticateUseCase authentication;
  private IManageUsersUseCase users;
  private LoginThrottle throttle;

  this(WebGuard guard, IAuthenticateUseCase authentication, IManageUsersUseCase users, LoginThrottle throttle) {
    this.guard = guard;
    this.authentication = authentication;
    this.users = users;
    this.throttle = throttle;
  }

  void registerRoutes(URLRouter router) {
    router.get("/login", &loginForm);
    router.post("/login", &login);
    router.post("/logout", &logout);
    router.get("/account", &account);
    router.post("/account/password", &changePassword);
  }

  void loginForm(HTTPServerRequest req, HTTPServerResponse res) {
    noStore(res);
    PageContext current;
    auto next = safeNext(req.query.get("next", ""));
    if (guard.tryCurrent(req, "", "", current)) {
      res.redirect(next);
      return;
    }
    renderLogin(res, 200, "", "", next);
  }

  void login(HTTPServerRequest req, HTTPServerResponse res) {
    noStore(res);
    if (!isSameOrigin(req)) {
      res.writeBody("Cross-origin request rejected", 403, "text/plain; charset=utf-8");
      return;
    }
    auto name = req.form.get("user", "").strip;
    auto password = req.form.get("password", "");
    auto next = safeNext(req.form.get("next", ""));
    auto key = name.toLower ~ "|" ~ req.clientAddress.toAddressString;

    auto locked = throttle.lockedFor(key);
    if (locked > Duration.zero) {
      auto minutes = locked.total!"minutes" + 1;
      renderLogin(res, 429, "Too many failed attempts. Try again in " ~ minutes.to!string ~ " minute"
          ~ (minutes == 1 ? "" : "s") ~ ".", name, next);
      return;
    }
    try {
      auto user = authentication.authenticate(name, password);
      throttle.success(key);
      guard.signIn(req, res, user.id);
      res.redirect(next, 303);
    } catch (AuthenticationException e) {
      throttle.failure(key);
      renderLogin(res, 401, e.msg, name, next);
    }
  }

  void logout(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.requirePost(req, res, "", "", false, page))
      return;
    guard.signOut(req, res);
    res.redirect("/login", 303);
  }

  void account(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "My account", "account", false, page))
      return;
    string message, error;
    res.render!("account.dt", page, message, error);
  }

  void changePassword(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.requirePost(req, res, "My account", "account", false, page))
      return;
    string message, error;
    auto replacement = req.form.get("password", "");
    if (replacement != req.form.get("confirm", ""))
      error = "The new passwords do not match";
    else
      try {
        users.changeOwnPassword(page.user.id, req.form.get("current", ""), replacement);
        guard.endOtherSessions(req, page.user.id);
        message = "Password changed. Other sessions of your account were signed out.";
      } catch (PlatformException e)
        error = e.msg;
    res.render!("account_form.dt", page, message, error);
  }

  private void renderLogin(HTTPServerResponse res, int status, string error, string userName, string next) {
    auto page = guard.anonymous("Sign in");
    res.statusCode = status;
    res.render!("login.dt", page, error, userName, next);
  }
}
