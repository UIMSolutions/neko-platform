/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web application firewall: request inspection rules, a per-client rate
/// limit and automatic bans. Framework-free, so the rules are unit-tested
/// here; presentation.http.firewall applies them to vibe.d requests.
///
/// Inspection looks at the method, the request URI (raw and decoded), the
/// User-Agent, and the values of query parameters and URL-encoded form
/// fields (not uploads). Fields that legitimately hold anything — passwords —
/// are skipped (`skipFields`).
module neko.platform.infrastructure.firewall.wafinspector;

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
import neko.platform.infrastructure.firewall.wafrequest;
import neko.platform.infrastructure.firewall.waffinding;

@safe:

/// The inspection rules. Holds compiled patterns; build once.
class WafInspector {
  private string[] skip;
  private Regex!char sqli, xss, rce;

  /// `skipFields`: field names whose values are not inspected.
  this(string[] skipFields = ["password", "confirm", "current"]) @trusted {
    skip = skipFields;
    sqli = regex(`(\bunion\b[\s\S]{0,40}\bselect\b)|(\b(or|and)\b\s*['"]?\s*\d+\s*['"]?\s*=\s*['"]?\s*\d+)|`
        ~ `('\s*(or|and)\s*'[^']*'\s*=\s*')|(;\s*(drop|truncate|alter)\s+(table|database|schema|index|view|user)\b)|`
        ~ `(;\s*(delete\s+from|insert\s+into|update\s+\w+\s+set)\b)|`
        ~ `(\b(sleep|benchmark|pg_sleep)\s*\()|(\bwaitfor\s+delay\b)|(\binformation_schema\b)|`
        ~ `(\bload_file\s*\()|(\binto\s+(out|dump)file\b)|(\bxp_cmdshell\b)|('\s*--)|(/\*!\d*)`);
    xss = regex(`(<\s*script\b)|(<\s*/\s*script\s*>)|(\bjavascript\s*:)|(\bvbscript\s*:)|(<[a-z!/][^>]*\son[a-z]+\s*=)|`
        ~ `(<\s*(iframe|object|embed|svg|math|base|meta|link)\b)|(\bdocument\s*\.\s*(cookie|domain|write))|`
        ~ `(\bsrcdoc\s*=)|(expression\s*\()`);
    rce = regex("([;&|`]\\s*(cat|ls|id|whoami|wget|curl|nc|ncat|bash|sh|zsh|python|perl|php|powershell|cmd)\\b)|"
        ~ "(\\$\\(\\s*\\w)|(\\$\\{(jndi|env|sys|java)\\s*:)|(/etc/(passwd|shadow|hosts)\\b)|(/bin/(ba)?sh\\b)|"
        ~ "(\\bcmd(\\.exe)?\\s*/c\\b)|(<\\?php)");
  }

  /// The first finding, if any.
  bool inspect(const WafRequest r, out WafFinding finding) @trusted {
    // ── protocol ─────────────────────────────────────────────────────────
    if (!r.method.among("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"))
      return found(finding, "protocol.method", "method", "HTTP method " ~ short_(r.method) ~ " is not used here");
    if (r.uri.length > 4096)
      return found(finding, "protocol.uri-length", "uri", "The request URI is longer than 4096 characters");
    auto rawLower = r.uri.toLower;
    if (rawLower.canFind("%00") || r.path.canFind('\0'))
      return found(finding, "protocol.null-byte", "uri", "Null byte in the request");
    if (rawLower.canFind("%25") && (rawLower.canFind("%252e") || rawLower.canFind("%252f") || rawLower.canFind("%255c")))
      return found(finding, "protocol.double-encoding", "uri", "Double-encoded path characters");

    // ── path ─────────────────────────────────────────────────────────────
    auto path = r.path.toLower;
    if (traversal(path) || rawLower.canFind("%2e%2e") || rawLower.canFind("..%2f") || rawLower.canFind("..%5c"))
      return found(finding, "lfi.traversal", "path", "Directory traversal in the path");
    foreach (probe; probes)
      if (path.startsWith(probe) || path.canFind("/" ~ probe[1 .. $]))
        return found(finding, "scanner.path", "path", "Probe for " ~ probe ~ ", which this platform does not serve");
    foreach (ext; [".php", ".asp", ".aspx", ".jsp", ".cgi", ".pl", ".env", ".bak", ".sql", ".ini", ".htaccess", ".htpasswd"])
      if (path.endsWith(ext) && !path.startsWith("/media/"))
        return found(finding, "scanner.path", "path", "Request for a " ~ ext ~ " file, which this platform does not serve");

    // ── client ───────────────────────────────────────────────────────────
    auto agent = r.userAgent.toLower;
    foreach (tool; scanners)
      if (agent.canFind(tool))
        return found(finding, "scanner.agent", "user-agent", "Request from the attack tool " ~ tool);

    // ── parameters ───────────────────────────────────────────────────────
    foreach (f; r.fields) {
      if (skip.canFind(f[0]))
        continue;
      auto value = normalize(f[1]);
      auto name = normalize(f[0]);
      auto where = "field '" ~ short_(f[0]) ~ "'";
      foreach (v; [value, name]) {
        if (v.length == 0)
          continue;
        if (v.canFind('\0'))
          return found(finding, "protocol.null-byte", where, "Null byte in a parameter");
        if (traversal(v))
          return found(finding, "lfi.traversal", where, "Directory traversal in a parameter");
        if (!matchFirst(v, sqli).empty)
          return found(finding, "sqli", where, "SQL injection pattern");
        if (!matchFirst(v, xss).empty)
          return found(finding, "xss", where, "Cross-site scripting pattern");
        if (!matchFirst(v, rce).empty)
          return found(finding, "rce", where, "Command or code injection pattern");
      }
    }
    return false;
  }

  private static bool found(out WafFinding f, string rule, string where, string description) pure nothrow {
    f = WafFinding(rule, where, description);
    return true;
  }
}

/// Paths of software this platform does not run; asked for only by scanners.
private immutable string[] probes = [
  "/.env", "/.git/", "/.git", "/.svn", "/.hg", "/.aws", "/.ssh", "/.ds_store", "/wp-admin", "/wp-login", "/wp-content",
  "/wp-includes", "/xmlrpc.php", "/phpmyadmin", "/pma/", "/myadmin", "/server-status", "/server-info", "/cgi-bin/",
  "/actuator", "/console/", "/manager/html", "/solr/", "/vendor/phpunit", "/boaform", "/hnap1", "/.well-known/security.txt.bak",
];

private immutable string[] scanners = [
  "sqlmap", "nikto", "nmap", "masscan", "zgrab", "dirbuster", "gobuster", "dirb/", "wpscan", "acunetix", "nessus",
  "nuclei", "openvas", "w3af", "havij", "jaeles", "feroxbuster", "ffuf", "wfuzz", "commix", "xsstrike",
];

private bool traversal(string s) pure nothrow {
  return s.canFind("../") || s.canFind("..\\") || s.canFind("/..") || s == "..";
}

/// Lower case, HTML entities and `+` decoded loosely, white space collapsed,
/// SQL comments removed: the forms attackers use to slip past patterns.
string normalize(string value) pure @trusted {
  auto v = value.toLower.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
    .replace("&#39;", "'").replace("&#x27;", "'").replace("/**/", " ");
  char[] result;
  bool white;
  foreach (char c; v) {
    if (c == '\t' || c == '\n' || c == '\r' || c == ' ' || c == '\v' || c == '\f') {
      if (!white)
        result ~= ' ';
      white = true;
    } else {
      result ~= c;
      white = false;
    }
  }
  return cast(string) result;
}

private string short_(string s) pure nothrow {
  return s.length > 40 ? s[0 .. 40] ~ "…" : s;
}

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
