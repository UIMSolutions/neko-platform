/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Clock adapter synchronised with the Network Time Protocol (SNTPv4,
/// RFC 4330) when a time server is reachable.
///
/// `now()` never touches the network: it returns the system time plus the
/// offset measured at the last successful synchronisation. Synchronisation
/// runs in the background (`start()`, vibe.d timer). Until the first server
/// answers — or when none is configured or reachable — the clock is the
/// system clock.
module neko.platform.infrastructure.clients.ntpclock;

import core.atomic : atomicLoad, atomicStore;
import core.time : Duration, dur, msecs, seconds;
import std.datetime.date : DateTime;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import vibe.core.core : runTask, setTimer, Timer;
import vibe.core.log : logDiagnostic, logInfo, logWarn;
import neko.platform.ports.services;

@safe:

/// The result of one successful NTP exchange.
struct NtpSample {
  /// Server time − local time, in hnsecs.
  long offset;
  /// Round-trip delay, in hnsecs.
  long delay;
  string server;
}

class NtpClock : IClock {
  private string[] servers;
  private Duration interval;
  private Duration timeout;
  private shared long offsetHnsecs;
  private shared bool synced;
  private SysTime lastSync;
  private string lastServer;
  private Timer timer;

  /// `servers`: host names or addresses (port 123); none = system clock.
  /// `interval`: how often to resynchronise (zero = only once at start).
  this(string[] servers, Duration interval = 3600.seconds, Duration timeout = 2.seconds) {
    this.servers = servers;
    this.interval = interval;
    this.timeout = timeout;
  }

  SysTime now() {
    return SysTime(Clock.currStdTime + atomicLoad(offsetHnsecs), UTC());
  }

  bool enabled() const {
    return servers.length > 0;
  }

  /// Whether a time server has answered (otherwise `now()` is the system time).
  bool isSynchronized() const {
    return atomicLoad(synced);
  }

  /// Current correction applied to the system time.
  Duration offset() const {
    return dur!"hnsecs"(atomicLoad(offsetHnsecs));
  }

  /// The server of the last synchronisation and when it happened (system time).
  string server() const {
    return lastServer;
  }

  SysTime synchronizedAt() const {
    return lastSync;
  }

  /// Synchronise now (in a task) and then every `interval`.
  void start() {
    if (!enabled)
      return;
    runTask(() nothrow { tick(); });
    if (interval > Duration.zero)
      timer = setTimer(interval, &tick, true);
  }

  void stop() {
    if (timer)
      timer.stop();
  }

  /// Query the servers in order; the first valid answer sets the offset.
  /// Returns false (offset unchanged) when none answers.
  bool synchronize() {
    foreach (host; servers) {
      try {
        auto sample = query(host, timeout);
        atomicStore(offsetHnsecs, sample.offset);
        atomicStore(synced, true);
        lastSync = Clock.currTime(UTC());
        lastServer = host;
        logDiagnostic("ntp: %s offset %s ms, delay %s ms", host, sample.offset / 10_000, sample.delay / 10_000);
        return true;
      } catch (Exception e)
        logDiagnostic("ntp: %s: %s", host, e.msg);
    }
    return false;
  }

  private void tick() nothrow {
    try {
      auto first = !isSynchronized;
      if (synchronize()) {
        if (first)
          logInfo("ntp: clock synchronised with %s (offset %s ms)", lastServer, offset.total!"msecs");
      } else if (first)
        logWarn("ntp: no time server reachable (%-(%s, %)) — using the system clock", servers);
      else
        logWarn("ntp: resynchronisation failed — keeping offset %s ms from %s", offset.total!"msecs", lastServer);
    } catch (Exception e) {
      try
        logWarn("ntp: %s", e.msg);
      catch (Exception) {
      }
    }
  }
}

/// One SNTP exchange with `host` (UDP port 123).
NtpSample query(string host, Duration timeout) @trusted {
  import std.socket : AddressFamily;
  import vibe.core.net : listenUDP, resolveHost;

  auto address = resolveHost(host, AddressFamily.INET, true, timeout);
  address.port = 123;
  auto udp = listenUDP(0);
  scope (exit)
    udp.close();

  auto t1 = Clock.currStdTime;
  udp.send(ntpRequest(t1), &address);
  ubyte[ntpPacketSize] buffer;
  auto answer = udp.recv(timeout, buffer[]);
  auto t4 = Clock.currStdTime;
  auto sample = evaluateNtpResponse(answer, t1, t4);
  sample.server = host;
  return sample;
}

// --- SNTP packet encoding (pure, unit tested) ---

enum ntpPacketSize = 48;

/// hnsecs (SysTime.stdTime) of 1900-01-01T00:00:00Z, the NTP era 0 epoch.
enum long ntpEpochStdTime = 599_266_080_000_000_000L;

/// Client request (LI 0, version 4, mode 3) carrying `t1` as transmit time.
ubyte[ntpPacketSize] ntpRequest(long t1) pure nothrow @nogc {
  ubyte[ntpPacketSize] p;
  p[0] = 0x23;
  writeTimestamp(p[40 .. 48], toNtpTimestamp(t1));
  return p;
}

/// Validate a server response and compute offset and delay (RFC 4330 §5).
/// `t1`: when the request was sent, `t4`: when the answer arrived (stdTime).
NtpSample evaluateNtpResponse(const(ubyte)[] p, long t1, long t4) pure {
  if (p.length < ntpPacketSize)
    throw new Exception("short NTP response");
  auto leap = p[0] >> 6;
  auto mode = p[0] & 0x07;
  auto stratum = p[1];
  if (mode != 4 && mode != 5)
    throw new Exception("not an NTP server response");
  if (leap == 3 || stratum == 0 || stratum > 15)
    throw new Exception("NTP server not synchronised (kiss-o'-death or unsynchronised)");
  // The server echoes our transmit time: protects against stray/forged answers.
  if (readTimestamp(p[24 .. 32]) != toNtpTimestamp(t1))
    throw new Exception("NTP response does not match the request");
  auto t2 = fromNtpTimestamp(readTimestamp(p[32 .. 40]));
  auto t3 = fromNtpTimestamp(readTimestamp(p[40 .. 48]));
  if (t3 == ntpEpochStdTime)
    throw new Exception("NTP response without transmit time");
  NtpSample s;
  s.offset = ((t2 - t1) + (t3 - t4)) / 2;
  s.delay = (t4 - t1) - (t3 - t2);
  return s;
}

ulong toNtpTimestamp(long stdTime) pure nothrow @nogc {
  auto since = stdTime - ntpEpochStdTime; // hnsecs since 1900 (era wraps in 2036 by truncation)
  auto secs = cast(ulong)(since / 10_000_000);
  auto frac = cast(ulong)(since % 10_000_000);
  return ((secs & 0xFFFF_FFFF) << 32) | ((frac << 32) / 10_000_000);
}

long fromNtpTimestamp(ulong ts) pure nothrow @nogc {
  long secs = ts >> 32;
  // Values ≥ 2^31 are era 0 (1968–2036); smaller ones belong to era 1
  // (after the rollover on 2036-02-07).
  if (secs < 0x8000_0000L)
    secs += 1L << 32;
  auto frac = cast(long)(((ts & 0xFFFF_FFFF) * 10_000_000 + (1UL << 31)) >> 32);
  return ntpEpochStdTime + secs * 10_000_000 + frac;
}

private void writeTimestamp(ubyte[] target, ulong ts) pure nothrow @nogc {
  foreach (i; 0 .. 8)
    target[i] = cast(ubyte)(ts >> (56 - 8 * i));
}

private ulong readTimestamp(const(ubyte)[] source) pure nothrow @nogc {
  ulong ts;
  foreach (i; 0 .. 8)
    ts = (ts << 8) | source[i];
  return ts;
}

unittest {
  assert(SysTime(DateTime(1900, 1, 1), UTC()).stdTime == ntpEpochStdTime);

  // Round trip of a timestamp (sub-µs precision).
  auto t = SysTime(DateTime(2026, 11, 26, 12, 0, 0), UTC()).stdTime + 1_234_567;
  assert(fromNtpTimestamp(toNtpTimestamp(t)) == t);
  // After the 2036 era rollover.
  auto t36 = SysTime(DateTime(2040, 1, 1), UTC()).stdTime;
  assert(fromNtpTimestamp(toNtpTimestamp(t36)) == t36);

  // Request: version 4, client mode, our transmit time.
  auto req = ntpRequest(t);
  assert(req[0] == 0x23);
  assert(readTimestamp(req[40 .. 48]) == toNtpTimestamp(t));
}

unittest {
  // A server 5 s ahead, 20 ms each way, 1 ms processing.
  auto t1 = SysTime(DateTime(2026, 11, 26, 12, 0, 0), UTC()).stdTime;
  auto ahead = 50_000_000L, leg = 200_000L, work = 10_000L;
  auto t2 = t1 + leg + ahead;
  auto t3 = t2 + work;
  auto t4 = t1 + 2 * leg + work;

  ubyte[ntpPacketSize] p;
  p[0] = 0x24; // LI 0, version 4, mode 4 (server)
  p[1] = 2;
  writeTimestamp(p[24 .. 32], toNtpTimestamp(t1));
  writeTimestamp(p[32 .. 40], toNtpTimestamp(t2));
  writeTimestamp(p[40 .. 48], toNtpTimestamp(t3));
  auto s = evaluateNtpResponse(p[], t1, t4);
  assert(s.offset == ahead);
  assert(s.delay == 2 * leg);

  import std.exception : assertThrown;

  auto wrongOrigin = p;
  writeTimestamp(wrongOrigin[24 .. 32], toNtpTimestamp(t1 + 1_000_000));
  assertThrown(evaluateNtpResponse(wrongOrigin[], t1, t4));
  auto kissOfDeath = p;
  kissOfDeath[1] = 0;
  assertThrown(evaluateNtpResponse(kissOfDeath[], t1, t4));
  auto client = p;
  client[0] = 0x23;
  assertThrown(evaluateNtpResponse(client[], t1, t4));
  assertThrown(evaluateNtpResponse(p[0 .. 40], t1, t4));
}

unittest {
  // Without servers (or before the first answer) it is the system clock.
  auto clock = new NtpClock(null);
  assert(!clock.enabled && !clock.isSynchronized);
  auto before = Clock.currTime(UTC());
  auto now = clock.now();
  assert(now >= before && now - before < 1.seconds);
  clock.start(); // no-op
}
