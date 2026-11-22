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
module neko.platform.infrastructure.firewall.waffinding;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;

@safe:

/// One finding of the inspection.
struct WafFinding {
  /// Stable rule id ("sqli", "lfi.traversal", …).
  string rule;
  /// What matched, shortened ("query 'q'", "path").
  string where;
  string description;
}
