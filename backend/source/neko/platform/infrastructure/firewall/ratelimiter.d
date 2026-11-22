module neko.platform.infrastructure.firewall.ratelimiter;

import core.time : Duration, minutes;
import std.algorithm : among, any, canFind, endsWith, startsWith;
import std.array : replace;
import std.datetime.systime : SysTime;
import std.regex : Regex, matchFirst, regex;
import std.string : indexOf, strip, toLower;
import std.uni : isWhite;

@safe:

/// At most `perMinute` requests per client and minute (fixed one-minute
/// windows). 0 = no limit.
class RateLimiter {
  private struct Window {
    long minute;
    long count;
  }

  private Window[string] windows;
  private long perMinute;

  this(long perMinute) {
    this.perMinute = perMinute;
  }

  long limit() const pure nothrow {
    return perMinute;
  }

  /// Count a request; false if the client is over its limit.
  bool allow(string client, SysTime now) nothrow {
    if (perMinute <= 0)
      return true;
    auto minute = now.stdTime / 600_000_000L;
    auto w = client in windows;
    if (w is null || w.minute != minute) {
      if (windows.length > 50_000)
        prune(minute);
      windows[client] = Window(minute, 1);
      return true;
    }
    return ++w.count <= perMinute;
  }

  private void prune(long minute) nothrow {
    string[] old;
    foreach (k, w; windows)
      if (w.minute != minute)
        old ~= k;
    foreach (k; old)
      windows.remove(k);
  }
}
