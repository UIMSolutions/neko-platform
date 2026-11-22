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
module neko.platform.infrastructure.firewall.helpers;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;

@safe:

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


