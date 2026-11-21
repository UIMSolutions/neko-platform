/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Access control for the server-rendered pages (vibe.web.web + vibe.web.auth).
///
/// The page controllers are web interfaces annotated `@requiresAuth`.
/// `mixin PageAuthentication` gives them the `authenticate` method, which
/// resolves the signed-in user from the session cookie (and checks origin and
/// CSRF token on POST). Its result, `PageContext`, is the vibe.web.auth info
/// object: every access right has a predicate, so a handler states what it
/// needs with `@auth(Role.usersManage)` and vibe.d answers 403 otherwise.
module neko.platform.presentation.web.guard;

import std.ascii : toUpper;
import vibe.data.json : Json;
import vibe.http.common : Cookie, HTTPMethod;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.textfilter.urlencode : urlEncode;
import neko.platform.application.dtos : UserDto;
import neko.platform.domain.enumerations.rights : AccessRight, key;
import neko.platform.ports.usecases : IAuthenticateUseCase;
import neko.platform.presentation.web.sessions;

@safe:

/// An entry of the main navigation.
struct NavItem {
  string key;
  string label;
  string href;
  string icon;
  AccessRight right;
}

/// Pages a user may see, in menu order (the account page is always there).
immutable NavItem[] navigation = [
  NavItem("status", "Status", "/status", "activity-heartbeat", AccessRight.statusRead),
  NavItem("monitoring", "Monitoring", "/monitoring", "chart-line", AccessRight.monitoringRead),
  NavItem("landscape", "Landscape", "/landscape", "hexagons", AccessRight.landscapeRead),
  NavItem("sites", "Sites", "/sites", "world", AccessRight.sitesRead),
  NavItem("files", "Files", "/files", "files", AccessRight.filesRead),
  NavItem("security", "Security", "/security", "shield-check", AccessRight.securityRead),
  NavItem("users", "Users", "/users", "users", AccessRight.usersRead),
  NavItem("roles", "Roles", "/roles", "shield-lock", AccessRight.rolesRead),
];

/// Data for layout.dt (header, navigation, CSRF token) and the vibe.web.auth
/// information of a request.
struct PageContext {
  string serviceName;
  string domain;
  string title;
  /// Key of the highlighted navigation entry ("status", "sites", "files", "users", …).
  string active;
  UserDto user;
  string csrf;

  /// For hx-headers on <body>: every htmx request carries the CSRF token.
  string htmxHeaders() const {
    return Json(["X-CSRF-Token": Json(csrf)]).toString;
  }

  bool can(AccessRight right) const pure nothrow {
    return user.can(right.key);
  }

  /// The same context for another page.
  PageContext at(string title, string active) {
    auto p = this;
    p.title = title;
    p.active = active;
    return p;
  }

  /// The navigation entries this user may open.
  immutable(NavItem)[] menu() const pure nothrow {
    immutable(NavItem)[] items;
    foreach (ref item; navigation)
      if (can(item.right))
        items ~= item;
    return items;
  }

  /// Where to go after sign-in: the first page the user may open.
  string home() const pure nothrow {
    auto items = menu;
    return items.length ? items[0].href : "/account";
  }

  string initials() const pure {
    import neko.platform.presentation.web.support : initial;

    return initial(user.label);
  }

  // vibe.web.auth role predicates: @auth(Role.usersManage) → isUsersManage()
  static foreach (name; __traits(allMembers, AccessRight))
    mixin("bool is" ~ upperFirst(name) ~ "() const pure nothrow { return can(AccessRight." ~ name ~ "); }");
}

private string upperFirst(string s) pure {
  return s.length ? toUpper(s[0]) ~ s[1 .. $] : s;
}

/// The vibe.web.auth hook of a page controller; it needs a field `guard`.
mixin template PageAuthentication() {
  @noRoute PageContext authenticate(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
    PageContext page;
    guard.authenticate(req, res, page);
    return page; // answered already (redirect or 403) if the request was refused
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

  /// Page context for an anonymous page (sign-in, error pages).
  PageContext anonymous(string title) const {
    return PageContext(serviceName, domain, title);
  }

  /// The signed-in user of the request, without writing a response.
  bool tryCurrent(scope HTTPServerRequest req, out PageContext page) {
    auto token = req.cookies.get(cookieName, "");
    WebSession session;
    if (!sessions.touch(token, session))
      return false;
    UserDto user;
    if (!authentication.tryActive(session.accountId, user)) {
      sessions.destroy(token); // account removed or deactivated
      return false;
    }
    page = PageContext(serviceName, domain, "", "", user, session.csrf);
    return true;
  }

  /// Resolves the signed-in user. Returns false after answering: with a
  /// redirect to the sign-in page (401 + HX-Redirect for htmx requests), or
  /// with 403 for a POST from another origin or without the CSRF token.
  bool authenticate(scope HTTPServerRequest req, scope HTTPServerResponse res, out PageContext page) {
    noStore(res);
    auto post = req.method == HTTPMethod.POST;
    if (post && !isSameOrigin(req)) {
      res.writeBody("Cross-origin request rejected", 403, "text/plain; charset=utf-8");
      return false;
    }
    if (!tryCurrent(req, page)) {
      toLogin(req, res);
      return false;
    }
    if (post) {
      auto sent = req.headers.get("X-CSRF-Token", "");
      if (sent.length == 0)
        sent = req.form.get("_csrf", "");
      if (!sameText(sent, page.csrf)) {
        res.writeBody("Invalid or missing CSRF token — reload the page", 403, "text/plain; charset=utf-8");
        return false;
      }
    }
    return true;
  }

  /// Start a session after a successful sign-in (always a fresh token).
  void signIn(scope HTTPServerRequest req, scope HTTPServerResponse res, string accountId) {
    auto old = req.cookies.get(cookieName, "");
    if (old.length > 0)
      sessions.destroy(old);
    setSessionCookie(req, res, sessions.create(accountId));
  }

  void signOut(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    sessions.destroy(req.cookies.get(cookieName, ""));
    setSessionCookie(req, res, null);
  }

  /// Sign an account out of its other sessions (after a password change).
  void endOtherSessions(scope HTTPServerRequest req, string accountId) {
    sessions.destroyAccount(accountId, req.cookies.get(cookieName, ""));
  }

  void endAllSessions(string accountId) {
    sessions.destroyAccount(accountId);
  }

  private void setSessionCookie(scope HTTPServerRequest req, scope HTTPServerResponse res, string value) {
    auto cookie = res.setCookie(cookieName, value, "/");
    cookie.httpOnly = true;
    cookie.sameSite = Cookie.SameSite.strict;
    cookie.secure = isHttps(req);
  }

  private void toLogin(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    if (req.headers.get("HX-Request", "") == "true") {
      res.headers["HX-Redirect"] = "/login";
      res.writeBody("Sign-in required", 401, "text/plain; charset=utf-8");
      return;
    }
    auto target = req.requestURI;
    res.redirect(target == "/status" || target == "/start" ? "/login" : "/login?next=" ~ urlEncode(target));
  }
}

/// Pages show personal data: keep them out of shared caches and history.
void noStore(scope HTTPServerResponse res) {
  res.headers["Cache-Control"] = "no-store";
}

///
unittest {
  PageContext page;
  page.user.rights = ["status.read", "roles.read"];
  assert(page.isStatusRead && page.isRolesRead && !page.isUsersRead && !page.isRolesManage);
  assert(page.menu.length == 2 && page.menu[1].key == "roles" && page.home == "/status");
  page.user.rights = ["files.read"];
  assert(page.isFilesRead && !page.isFilesManage && page.home == "/files");
  page.user.rights = null;
  assert(page.menu.length == 0 && page.home == "/account");
}
