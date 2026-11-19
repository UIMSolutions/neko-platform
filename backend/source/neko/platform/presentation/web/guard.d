/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Access control for the server-rendered pages: resolves the signed-in user
/// from the session cookie and builds the data every page template needs.
module neko.platform.presentation.web.guard;

import vibe.data.json : Json;
import vibe.http.common : Cookie;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.textfilter.urlencode : urlEncode;
import neko.platform.application.dtos : UserDto;
import neko.platform.ports.usecases : IAuthenticateUseCase;
import neko.platform.presentation.web.sessions;

@safe:

/// Data for layout.dt (header, navigation, CSRF token).
struct PageContext {
  string serviceName;
  string domain;
  string title;
  /// Key of the highlighted navigation entry ("status", "users", "account").
  string active;
  UserDto user;
  string csrf;
  /// For hx-headers on <body>: every htmx request carries the CSRF token.
  string htmxHeaders() const {
    return Json(["X-CSRF-Token": Json(csrf)]).toString;
  }
}

class WebGuard {
  private WebSessions sessions;
  private IAuthenticateUseCase authentication;
  private string serviceName;
  private string domain;
  /// One cookie per domain: the four platform binaries often run on one host,
  /// and browsers do not separate cookies by port.
  immutable string cookieName;

  this(WebSessions sessions, IAuthenticateUseCase authentication, string serviceName, string domain) {
    this.sessions = sessions;
    this.authentication = authentication;
    this.serviceName = serviceName;
    this.domain = domain;
    this.cookieName = "neko_session_" ~ domain;
  }

  /// Page context for an anonymous page (sign-in).
  PageContext anonymous(string title) const {
    return PageContext(serviceName, domain, title);
  }

  /// The signed-in user of the request, without writing a response.
  bool tryCurrent(scope HTTPServerRequest req, string title, string active, out PageContext page) {
    auto token = req.cookies.get(cookieName, "");
    WebSession session;
    if (!sessions.touch(token, session))
      return false;
    UserDto user;
    if (!authentication.tryActive(session.accountId, user)) {
      sessions.destroy(token); // account removed or deactivated
      return false;
    }
    page = PageContext(serviceName, domain, title, active, user, session.csrf);
    return true;
  }

  /// For GET handlers. Returns false after answering with a redirect to the
  /// sign-in page (401 for htmx requests) or 403 for non-administrators.
  bool require(HTTPServerRequest req, HTTPServerResponse res, string title, string active, bool adminOnly,
      out PageContext page) {
    noStore(res);
    if (!tryCurrent(req, title, active, page)) {
      toLogin(req, res);
      return false;
    }
    if (adminOnly && !page.user.isAdmin) {
      res.writeBody("Administrator role required", 403, "text/plain; charset=utf-8");
      return false;
    }
    return true;
  }

  /// For POST handlers: additionally checks the origin and the CSRF token.
  bool requirePost(HTTPServerRequest req, HTTPServerResponse res, string title, string active, bool adminOnly,
      out PageContext page) {
    if (!isSameOrigin(req)) {
      res.writeBody("Cross-origin request rejected", 403, "text/plain; charset=utf-8");
      return false;
    }
    if (!require(req, res, title, active, adminOnly, page))
      return false;
    auto sent = req.headers.get("X-CSRF-Token", "");
    if (sent.length == 0)
      sent = req.form.get("_csrf", "");
    if (!sameText(sent, page.csrf)) {
      res.writeBody("Invalid or missing CSRF token — reload the page", 403, "text/plain; charset=utf-8");
      return false;
    }
    return true;
  }

  /// Start a session after a successful sign-in (always a fresh token).
  void signIn(HTTPServerRequest req, HTTPServerResponse res, string accountId) {
    auto old = req.cookies.get(cookieName, "");
    if (old.length > 0)
      sessions.destroy(old);
    setSessionCookie(req, res, sessions.create(accountId));
  }

  void signOut(HTTPServerRequest req, HTTPServerResponse res) {
    sessions.destroy(req.cookies.get(cookieName, ""));
    setSessionCookie(req, res, null);
  }

  /// Sign an account out of its other sessions (after a password change).
  void endOtherSessions(HTTPServerRequest req, string accountId) {
    sessions.destroyAccount(accountId, req.cookies.get(cookieName, ""));
  }

  void endAllSessions(string accountId) {
    sessions.destroyAccount(accountId);
  }

  private void setSessionCookie(HTTPServerRequest req, HTTPServerResponse res, string value) {
    auto cookie = res.setCookie(cookieName, value, "/");
    cookie.httpOnly = true;
    cookie.sameSite = Cookie.SameSite.strict;
    cookie.secure = isHttps(req);
  }

  private void toLogin(HTTPServerRequest req, HTTPServerResponse res) {
    if (req.headers.get("HX-Request", "") == "true") {
      res.headers["HX-Redirect"] = "/login";
      res.writeBody("Sign-in required", 401, "text/plain; charset=utf-8");
      return;
    }
    auto target = req.requestURI;
    res.redirect(target == "/status" ? "/login" : "/login?next=" ~ urlEncode(target));
  }
}

/// Pages show personal data: keep them out of shared caches and history.
void noStore(scope HTTPServerResponse res) {
  res.headers["Cache-Control"] = "no-store";
}
