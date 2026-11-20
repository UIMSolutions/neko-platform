/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Network traffic: requests and bytes per client address and minute, and
/// the security events of the firewall. In memory, since the start.
module neko.platform.infrastructure.monitoring.traffic;

import core.time : MonoTime;
import std.algorithm : max, sort;
import std.datetime.systime : SysTime;

@safe:

/// Traffic of one client address.
struct ClientTraffic {
  string address;
  long requests;
  long bytesIn;
  long bytesOut;
  long clientErrors;
  long serverErrors;
  /// Refused by the firewall (rules, IP lists, bans, rate limit).
  long blocked;
  SysTime firstSeen;
  SysTime lastSeen;
  string lastUserAgent;
  string lastPath;
}

/// Something the firewall did (or would have done, in detect mode).
struct SecurityEvent {
  SysTime at;
  string client;
  /// "waf" | "network" | "ban" | "rate-limit"
  string kind;
  /// Rule id ("sqli", "iplist", …).
  string rule;
  string method;
  string path;
  string detail;
  /// False in detect mode.
  bool blocked;
}

struct TrafficSnapshot {
  long requests;
  long bytesIn;
  long bytesOut;
  long blocked;
  long detected;
  long clients;
  /// Per minute, oldest first, the last entry is the current minute.
  long[] bytesInPerMinute;
  long[] bytesOutPerMinute;
  long[] blockedPerMinute;
  /// By requests, the busiest first.
  ClientTraffic[] top;
  SecurityEvent[] events;
  long[string] byRule;
}

class TrafficMonitor {
  private {
    ClientTraffic[string] clients;
    size_t maxClients;
    long requests, bytesIn, bytesOut, blocked, detected;
    long[60] inRing, outRing, blockedRing;
    long minuteOfLast = -1;
    MonoTime started;
    SecurityEvent[] events;
    size_t keepEvents;
    long[string] byRule;
  }

  this(size_t maxClients = 2000, size_t keepEvents = 200) {
    this.maxClients = maxClients;
    this.keepEvents = keepEvents;
    started = MonoTime.currTime;
  }

  void record(string address, SysTime at, long inBytes, long outBytes, int status, string userAgent, string path) nothrow {
    tick();
    requests++;
    bytesIn += inBytes;
    bytesOut += outBytes;
    inRing[minuteOfLast % 60] += inBytes;
    outRing[minuteOfLast % 60] += outBytes;
    auto c = client(address, at);
    c.requests++;
    c.bytesIn += inBytes;
    c.bytesOut += outBytes;
    if (status >= 500)
      c.serverErrors++;
    else if (status >= 400)
      c.clientErrors++;
    c.lastSeen = at;
    c.lastUserAgent = userAgent.length > 160 ? userAgent[0 .. 160] : userAgent;
    c.lastPath = path.length > 160 ? path[0 .. 160] : path;
  }

  void security(SecurityEvent e) nothrow {
    tick();
    if (e.blocked) {
      blocked++;
      blockedRing[minuteOfLast % 60]++;
      client(e.client, e.at).blocked++;
    } else
      detected++;
    byRule[e.rule]++;
    events ~= e;
    if (events.length > keepEvents + keepEvents / 4)
      events = events[$ - keepEvents .. $].dup;
  }

  TrafficSnapshot snapshot(size_t top = 25) {
    tick();
    TrafficSnapshot s;
    s.requests = requests;
    s.bytesIn = bytesIn;
    s.bytesOut = bytesOut;
    s.blocked = blocked;
    s.detected = detected;
    s.clients = cast(long) clients.length;
    foreach (i; 0 .. 60) {
      auto m = minuteOfLast - 59 + i;
      s.bytesInPerMinute ~= m < 0 ? 0 : inRing[m % 60];
      s.bytesOutPerMinute ~= m < 0 ? 0 : outRing[m % 60];
      s.blockedPerMinute ~= m < 0 ? 0 : blockedRing[m % 60];
    }
    auto all = clients.values;
    all.sort!((a, b) => a.requests + a.blocked > b.requests + b.blocked);
    s.top = all.length > top ? all[0 .. top] : all;
    foreach_reverse (e; events)
      s.events ~= e;
    s.byRule = byRule.dup;
    return s;
  }

  bool tryClient(string address, out ClientTraffic c) {
    if (auto p = address in clients) {
      c = *p;
      return true;
    }
    return false;
  }

  private ClientTraffic* client(string address, SysTime at) nothrow {
    auto key = address.length ? address : "local";
    auto c = key in clients;
    if (c is null) {
      if (clients.length >= maxClients)
        evict();
      clients[key] = ClientTraffic(key);
      c = key in clients;
      c.firstSeen = at;
    }
    return c;
  }

  /// Drop the quietest tenth when the table is full.
  private void evict() nothrow {
    try {
      auto all = clients.values;
      all.sort!((a, b) => a.lastSeen < b.lastSeen);
      foreach (c; all[0 .. max(1, all.length / 10)])
        clients.remove(c.address);
    } catch (Exception) {
    }
  }

  private void tick() nothrow {
    auto now = (MonoTime.currTime - started).total!"minutes";
    if (minuteOfLast < 0)
      minuteOfLast = 0;
    while (minuteOfLast < now) {
      minuteOfLast++;
      inRing[minuteOfLast % 60] = 0;
      outRing[minuteOfLast % 60] = 0;
      blockedRing[minuteOfLast % 60] = 0;
    }
  }
}

///
unittest {
  auto t = new TrafficMonitor(3, 2);
  auto at = SysTime.fromISOExtString("2026-11-20T10:00:00Z");
  t.record("10.0.0.1", at, 100, 2000, 200, "Mozilla", "/");
  t.record("10.0.0.1", at, 50, 10, 404, "curl/8", "/x");
  t.record("10.0.0.2", at, 0, 500, 500, "", "/files");
  t.security(SecurityEvent(at, "10.0.0.9", "waf", "sqli", "GET", "/", "x", true));
  t.security(SecurityEvent(at, "10.0.0.9", "waf", "xss", "GET", "/", "x", false));
  auto s = t.snapshot;
  assert(s.requests == 3 && s.bytesIn == 150 && s.bytesOut == 2510 && s.blocked == 1 && s.detected == 1);
  assert(s.top[0].address == "10.0.0.1" && s.top[0].clientErrors == 1 && s.top[0].lastUserAgent == "curl/8");
  assert(s.clients == 3 && s.events.length == 2 && s.events[0].rule == "xss" && s.byRule["sqli"] == 1);
  assert(s.bytesOutPerMinute[$ - 1] == 2510);
  t.record("10.0.0.3", at, 1, 1, 200, "", "/"); // full: evicts the oldest
  assert(t.snapshot.clients <= 3);
}
