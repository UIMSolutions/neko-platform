/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Sign-in, sign-out and the own account (web interface).
///
///   GET  /login              sign-in form (?next=<local path>)
///   POST /login              user, password, next
///   POST /logout
///   GET  /start              redirect to the first page the user may open
///   GET  /account            own account: profile, roles, effective rights
///   POST /account/password   current, password, confirm (htmx: returns the form)
module neko.platform.presentation.web.auth;

import core.time : Duration;
import std.conv : to;
import std.string : strip, toLower;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : AccessRightDto;
import neko.platform.domain : AuthenticationException, PlatformException;
import neko.platform.ports.usecases : IAuthenticateUseCase, IManageRolesUseCase, IManageUsersUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.sessions;
import neko.platform.presentation.http.firewall : clientAddressOf;

@safe:

@requiresAuth
class AuthWeb {
  private WebGuard guard;
  private IAuthenticateUseCase authentication;
  private IManageUsersUseCase users;
  private IManageRolesUseCase roles;
  private LoginThrottle throttle;

  mixin PageAuthentication;

  this(WebGuard guard, IAuthenticateUseCase authentication, IManageUsersUseCase users, IManageRolesUseCase roles,
      LoginThrottle throttle) {
    this.guard = guard;
    this.authentication = authentication;
    this.users = users;
    this.roles = roles;
    this.throttle = throttle;
  }

  @noAuth @path("/login")
  void getLogin(HTTPServerRequest req, HTTPServerResponse res, string next = "") {
    noStore(res);
    PageContext current;
    if (guard.tryCurrent(req, current)) {
      res.redirect(safeNext(next));
      return;
    }
    renderLogin(res, 200, "", "", safeNext(next));
  }

  @noAuth @path("/login")
  void postLogin(HTTPServerRequest req, HTTPServerResponse res, string user = "", string password = "",
      string next = "") {
    noStore(res);
    if (!isSameOrigin(req)) {
      res.writeBody("Cross-origin request rejected", 403, "text/plain; charset=utf-8");
      return;
    }
    auto name = user.strip;
    next = safeNext(next);
    auto key = name.toLower ~ "|" ~ clientAddressOf(req); // the real client, also behind a proxy

    auto locked = throttle.lockedFor(key);
    if (locked > Duration.zero) {
      auto minutes = locked.total!"minutes" + 1;
      renderLogin(res, 429, "Too many failed attempts. Try again in " ~ minutes.to!string ~ " minute"
          ~ (minutes == 1 ? "" : "s") ~ ".", name, next);
      return;
    }
    try {
      auto account = authentication.authenticate(name, password);
      throttle.success(key);
      guard.signIn(req, res, account.id);
      res.redirect(next, 303);
    } catch (AuthenticationException e) {
      throttle.failure(key);
      renderLogin(res, 401, e.msg, name, next);
    }
  }

  @anyAuth @path("/logout")
  void postLogout(HTTPServerRequest req, HTTPServerResponse res) {
    guard.signOut(req, res);
    res.redirect("/login", 303);
  }

  @anyAuth @path("/start")
  void getStart(PageContext page, HTTPServerResponse res) {
    res.redirect(page.home);
  }

  @anyAuth @path("/account")
  void getAccount(PageContext page) {
    page = page.at("My account", "account");
    string message, error;
    auto catalogue = roles.rights();
    render!("account.dt", page, message, error, catalogue);
  }

  @anyAuth @path("/account/password")
  void postPassword(PageContext page, HTTPServerRequest req, string current = "", string password = "",
      string confirm = "") {
    string message, error;
    if (password != confirm)
      error = "The new passwords do not match";
    else
      try {
        users.changeOwnPassword(page.user.id, current, password);
        guard.endOtherSessions(req, page.user.id);
        message = "Password changed. Other sessions of your account were signed out.";
      } catch (PlatformException e)
        error = e.msg;
    render!("account_form.dt", page, message, error);
  }

  @noRoute void renderLogin(HTTPServerResponse res, int status, string error, string userName, string next) {
    auto page = guard.anonymous("Sign in");
    res.statusCode = status;
    render!("login.dt", page, error, userName, next);
  }
}
