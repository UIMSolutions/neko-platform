module neko.platform.infrastructure.firewall.banlist;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;
import neko.platform.infrastructure.firewall.ban;

@safe:

/// Bans clients that keep violating the rules: `threshold` findings within
/// `window` ban the client for `duration`. 0 = no automatic bans.
class BanList {
  private SysTime[][string] strikes;
  private Ban[string] bans;
  private long threshold;
  private Duration window, duration;

  this(long threshold, Duration duration, Duration window = 10.minutes) {
    this.threshold = threshold;
    this.duration = duration;
    this.window = window;
  }

  /// Count a violation; true if it caused a ban.
  bool strike(string client, SysTime now, string reason) nothrow {
    if (threshold <= 0 || client.length == 0)
      return false;
    SysTime[] recent;
    auto previous = client in strikes;
    foreach (t; previous ? *previous : null)
      if (now - t < window)
        recent ~= t;
    recent ~= now;
    if (recent.length >= threshold) {
      strikes.remove(client);
      bans[client] = Ban(client, now, now + duration, reason);
      return true;
    }
    strikes[client] = recent;
    return false;
  }

  void ban(string client, SysTime now, Duration length, string reason) nothrow {
    bans[client] = Ban(client, now, now + length, reason, true);
  }

  bool unban(string client) nothrow {
    strikes.remove(client);
    return bans.remove(client);
  }

  bool isBanned(string client, SysTime now, out Ban ban) nothrow {
    if (client in bans) {
      auto b = bans[client];
      if (now < b.until) {
        ban = b;
        return true;
      }
      bans.remove(client);
    }
    return false;
  }

  /// Current bans, the newest first.
  Ban[] active(SysTime now) {
    import std.algorithm;
    import std.array;

    Ban[] list = bans.byValue.filter!(b => now < b.until).array;
    list.sort!((a, b) => a.since > b.since);
    return list;
  }
}
