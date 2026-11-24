module neko.platform.infrastructure.firewall.tests;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;
import neko.platform.infrastructure.firewall.ban;
import neko.platform.infrastructure.firewall.banlist;
import neko.platform.infrastructure.firewall.ratelimiter;
import neko.platform.infrastructure.firewall.waffinding;
import neko.platform.infrastructure.firewall.wafinspector;
import neko.platform.infrastructure.firewall.wafrequest;

@safe:

///
unittest {
  auto waf = new WafInspector;
  WafFinding f;
  WafRequest ok = WafRequest("GET", "/files?site=shop&kind=image", "/files", "Mozilla/5.0",
    [["site", "shop"], ["kind", "image"]]);
  assert(!waf.inspect(ok, f));
  // normal text that only looks a little like code passes
  assert(!waf.inspect(WafRequest("POST", "/sites/shop/content", "/sites/shop/content", "Mozilla",
      [["body", "Select the colour you like, or call us: 1 = one."], ["title", "Fish & chips; drop by!"]]), f));
  assert(!waf.inspect(WafRequest("POST", "/login", "/login", "", [["password", "' or 1=1 --<script>"]]), f));

  string rule(WafRequest r) {
    WafFinding x;
    return waf.inspect(r, x) ? x.rule : "";
  }

  WafRequest q(string value) {
    return WafRequest("GET", "/?q=x", "/", "Mozilla", [["q", value]]);
  }

  assert(rule(q("1' OR '1'='1")) == "sqli");
  assert(rule(q("1 UNION/**/SELECT password FROM users")) == "sqli");
  assert(rule(q("x'; DROP TABLE users")) == "sqli");
  assert(rule(q("1 or 1=1")) == "sqli");
  assert(rule(q("<ScRipt>alert(1)</script>")) == "xss");
  assert(rule(q("<img src=x onerror=alert(1)>")) == "xss");
  assert(rule(q("javascript:alert(1)")) == "xss");
  assert(rule(q("&lt;svg onload=alert(1)&gt;")) == "xss");
  assert(rule(q("; cat /etc/passwd")) == "rce");
  assert(rule(q("${jndi:ldap://x/a}")) == "rce");
  assert(rule(q("../../etc/passwd")) == "lfi.traversal");
  assert(rule(WafRequest("GET", "/media/%2e%2e/x", "/media/../x", "")) == "lfi.traversal");
  assert(rule(WafRequest("GET", "/x%00.png", "/x", "")) == "protocol.null-byte");
  assert(rule(WafRequest("GET", "/%252e%252e/", "/%2e%2e/", "")) == "protocol.double-encoding");
  assert(rule(WafRequest("TRACE", "/", "/", "")) == "protocol.method");
  assert(rule(WafRequest("GET", "/.env", "/.env", "")) == "scanner.path");
  assert(rule(WafRequest("GET", "/wp-login.php", "/wp-login.php", "")) == "scanner.path");
  assert(rule(WafRequest("GET", "/index.php", "/index.php", "")) == "scanner.path");
  assert(rule(WafRequest("GET", "/media/shop/1/notes.sql", "/media/shop/1/notes.sql", "")) == "");
  assert(rule(WafRequest("GET", "/", "/", "sqlmap/1.7")) == "scanner.agent");
  assert(rule(WafRequest("GET", "/?" ~ "a".replicate(5000), "/", "")) == "protocol.uri-length");
}

///
unittest {
  import core.time : seconds;

  auto t0 = SysTime.fromISOExtString("2026-11-20T10:00:05Z");
  auto limiter = new RateLimiter(3);
  foreach (i; 0 .. 3)
    assert(limiter.allow("a", t0));
  assert(!limiter.allow("a", t0) && limiter.allow("b", t0));
  assert(limiter.allow("a", t0 + 60.seconds)); // next minute
  assert(new RateLimiter(0).allow("a", t0));

  auto bans = new BanList(3, 15.minutes);
  Ban b;
  assert(!bans.strike("x", t0, "sqli") && !bans.strike("x", t0 + 1.seconds, "sqli"));
  assert(!bans.strike("x", t0 + 11.minutes, "sqli")); // the first two expired
  assert(!bans.strike("x", t0 + 12.minutes, "sqli") && bans.strike("x", t0 + 13.minutes, "xss"));
  assert(bans.isBanned("x", t0 + 14.minutes, b) && b.reason == "xss" && !b.manual);
  assert(!bans.isBanned("x", t0 + 29.minutes, b));
  bans.ban("y", t0, 60.minutes, "manual");
  assert(bans.active(t0).length == 1 && bans.unban("y") && bans.active(t0).length == 0);
}

version (unittest) import std.array : replicate;
