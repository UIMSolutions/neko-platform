module neko.platform.infrastructure.firewall.ban;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;

@safe:

/// A banned address.
struct Ban {
  string client;
  SysTime since;
  SysTime until;
  string reason;
  /// Set by an administrator (not automatic).
  bool manual;
}
