/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web sign-in state: in-memory sessions with idle timeout, a sign-in
/// throttle, and the browser-side request checks (same origin, CSRF token).
///
/// Sessions live in the process: a restart signs everybody out, and several
/// replicas of one domain would need sticky sessions.
module neko.platform.presentation.web.sessions;

import core.time : Duration, minutes;
import std.algorithm : min, minElement;
import std.datetime.systime : SysTime;
import std.string : startsWith, strip;
import vibe.http.server : HTTPServerRequest;
import neko.platform.ports.services : IClock, IPasswordHasher;

@safe:

struct WebSession {
  string accountId;
  /// Sent back in the X-CSRF-Token header (htmx) or the _csrf form field.
  string csrf;
  SysTime lastSeen;
}

class WebSessions {
  private WebSession[string] sessions;
  private IPasswordHasher random;
  private IClock clock;
  private Duration idle;
  private size_t limit;

  this(IPasswordHasher random, IClock clock, Duration idle, size_t limit = 10_000) {
    this.random = random;
    this.clock = clock;
    this.idle = idle;
    this.limit = limit;
  }

  /// A new session; returns its token (the cookie value).
  string create(string accountId) {
    auto now = clock.now;
    prune(now);
    if (sessions.length >= limit) // drop the least recently used one
      sessions.remove(sessions.byKeyValue.minElement!(kv => kv.value.lastSeen).key);
    auto token = random.randomSecret();
    sessions[token] = WebSession(accountId, random.randomSecret(), now);
    return token;
  }

  /// The live session for the token; refreshes its idle timer.
  bool touch(string token, out WebSession session) {
    if (token.length == 0)
      return false;
    auto p = token in sessions;
    if (p is null)
      return false;
    auto now = clock.now;
    if (now - p.lastSeen > idle) {
      sessions.remove(token);
      return false;
    }
    p.lastSeen = now;
    session = *p;
    return true;
  }

  void destroy(string token) {
    sessions.remove(token);
  }

  /// Sign an account out everywhere except, optionally, one session.
  void destroyAccount(string accountId, string exceptToken = "") {
    string[] doomed;
    foreach (token, s; sessions)
      if (s.accountId == accountId && token != exceptToken)
        doomed ~= token;
    foreach (token; doomed)
      sessions.remove(token);
  }

  size_t length() const {
    return sessions.length;
  }

  private void prune(SysTime now) {
    string[] expired;
    foreach (token, s; sessions)
      if (now - s.lastSeen > idle)
        expired ~= token;
    foreach (token; expired)
      sessions.remove(token);
  }
}

/// Locks a user name / client address pair after repeated failed sign-ins.
class LoginThrottle {
  enum maxFailures = 5;
  private struct Entry {
    int failures;
    SysTime first;
    SysTime lockedUntil;
  }

  private Entry[string] entries;
  private IClock clock;
  private Duration window;

  this(IClock clock, Duration window = 15.minutes) {
    this.clock = clock;
    this.window = window;
  }

  /// Remaining lock time (Duration.zero = not locked).
  Duration lockedFor(string key) {
    if (auto e = key in entries) {
      auto left = e.lockedUntil - clock.now;
      if (left > Duration.zero)
        return left;
    }
    return Duration.zero;
  }

  void failure(string key) {
    auto now = clock.now;
    if (entries.length > 10_000)
      entries = null; // bounded memory under a flood; locks restart from zero
    auto e = key in entries;
    if (e is null || now - e.first > window) {
      entries[key] = Entry(1, now);
      return;
    }
    if (++e.failures >= maxFailures)
      e.lockedUntil = now + window;
  }

  void success(string key) {
    entries.remove(key);
  }
}

/// True if the request comes from a page of this server. Browsers send Origin
/// on every POST; requests without Origin and Referer (non-browser clients)
/// pass, because a cross-site form post always carries one of them.
bool isSameOrigin(scope HTTPServerRequest req) {
  auto source = req.headers.get("Origin", "");
  if (source.length == 0) {
    auto referer = req.headers.get("Referer", "");
    if (referer.length == 0)
      return true;
    source = originOf(referer);
  }
  if (source == "null")
    return false;
  foreach (host; [req.headers.get("X-Forwarded-Host", ""), req.headers.get("Host", "")])
    if (host.length > 0 && (source == "http://" ~ host.strip || source == "https://" ~ host.strip))
      return true;
  return false;
}

/// "https://host:1/path?q" → "https://host:1"
string originOf(string url) pure {
  import std.string : indexOf;

  auto scheme = url.indexOf("://");
  if (scheme < 0)
    return "";
  auto rest = url[scheme + 3 .. $];
  auto slash = rest.indexOf('/');
  return url[0 .. scheme + 3] ~ (slash < 0 ? rest : rest[0 .. slash]);
}

bool isHttps(scope HTTPServerRequest req) {
  return req.tls || req.headers.get("X-Forwarded-Proto", "") == "https";
}

/// Comparison without early exit.
bool sameText(string a, string b) pure nothrow {
  uint diff = a.length != b.length;
  foreach (i; 0 .. min(a.length, b.length))
    diff |= a[i] ^ b[i];
  return diff == 0;
}

/// Only local paths are followed after sign-in (no open redirects).
string safeNext(string next) pure {
  if (next.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\"))
    return next;
  return "/status";
}

///
unittest {
  import core.time : seconds;
  import neko.platform.application.services : FixedClock;

  class Counter : IPasswordHasher {
    int n;
    string hash(string p) {
      return p;
    }

    bool verify(string p, string h) {
      return p == h;
    }

    string randomSecret() {
      import std.conv : to;

      return "t" ~ (++n).to!string;
    }
  }

  auto clock = new FixedClock(SysTime(0));
  auto sessions = new WebSessions(new Counter, clock, 10.minutes, 2);
  auto a = sessions.create("alice");
  WebSession s;
  assert(sessions.touch(a, s) && s.accountId == "alice" && s.csrf.length > 0);
  assert(!sessions.touch("forged", s) && !sessions.touch("", s));

  clock.time += 11.minutes; // idle timeout
  assert(!sessions.touch(a, s));

  auto b = sessions.create("bob");
  clock.time += 1.seconds;
  sessions.create("carol");
  sessions.create("dave"); // over the limit: bob (least recently used) goes
  assert(sessions.length == 2 && !sessions.touch(b, s));
  sessions.destroyAccount("carol");
  assert(sessions.length == 1);

  auto throttle = new LoginThrottle(clock);
  foreach (i; 0 .. LoginThrottle.maxFailures - 1)
    throttle.failure("jane|1.2.3.4");
  assert(throttle.lockedFor("jane|1.2.3.4") == Duration.zero);
  throttle.failure("jane|1.2.3.4");
  assert(throttle.lockedFor("jane|1.2.3.4") > Duration.zero);
  clock.time += 16.minutes;
  assert(throttle.lockedFor("jane|1.2.3.4") == Duration.zero);

  assert(originOf("https://h:8181/users?x") == "https://h:8181" && originOf("garbage") == "");
  assert(safeNext("/users") == "/users" && safeNext("//evil.example") == "/status");
  assert(safeNext("https://evil.example") == "/status" && safeNext("/\\evil") == "/status");
  assert(sameText("abc", "abc") && !sameText("abc", "abd") && !sameText("abc", "ab"));
}
