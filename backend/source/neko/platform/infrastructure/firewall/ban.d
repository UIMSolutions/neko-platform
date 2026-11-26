module neko.platform.infrastructure.firewall.ban;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;
import uim.jsons;

@safe:

/// A banned address.
struct Ban {
  string client;
  SysTime since;
  SysTime until;
  string reason;
  /// Set by an administrator (not automatic).
  bool manual;

  // Json toJson() const {
    // import uim.jsons;
// 
    // return Json.emptyObject
      // .set("client", client)
      // .set("since", since)
      // .set("until", until)
      // .set("reason", reason)
      // .set("manual", manual);
  // }

  // static Ban fromJson(Json json) {
    // auto b = Ban();
    // b.client = json.getString("client", "");
    // b.since = json.hasKey("since") ? json.getString("since") : SysTime.min;
    // b.until = json.hasKey("until") ? json.getString("until") : SysTime.min;
    // b.reason = json.getString("reason", "");
    // b.manual = json.getBoolean("manual", false);
    // return b;
  // }
}
