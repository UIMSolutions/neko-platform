/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Monitoring: request metrics (in memory, since the start), the recent log
/// (a vibe.d logger keeping the last lines), and log files rotated daily.
///
///   RequestMetrics     counters, latency histogram, per-area figures, the
///                      last requests and failures (fed by presentation.http.RequestMonitor)
///   LogBuffer          the last log lines, for the monitoring page
///   DailyLogFile       <dir>/<prefix>-YYYY-MM-DD.<ext>, old files removed
///   FileLogWriter      the application log into a DailyLogFile
module neko.platform.infrastructure.monitoring;

public import neko.platform.infrastructure.monitoring.traffic;

import core.time : Duration, MonoTime, minutes;
import std.algorithm : max, min, sort;
import std.array : array;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.format : format;
import vibe.core.log : Logger, LogLevel, LogLine;

@safe:

/// Upper bounds of the latency buckets, in milliseconds (the last is +Inf).
immutable double[] latencyBuckets = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000];

/// One finished request.
struct RequestSample {
  SysTime at;
  string method;
  string path;
  /// Area of the platform ("pages", "files", "rest", …), see `areaOf`.
  string area;
  int status;
  double milliseconds;
  string client;
}

/// Figures of one area.
struct AreaStats {
  string area;
  long requests;
  long clientErrors;
  long serverErrors;
  double totalMilliseconds = 0;
  double maxMilliseconds = 0;

  double averageMilliseconds() const pure nothrow {
    return requests ? totalMilliseconds / requests : 0;
  }
}

/// Everything the monitoring page and /metrics show, at one moment.
struct MetricsSnapshot {
  SysTime startedAt;
  Duration uptime;
  long requests;
  long inFlight;
  /// Index = first digit of the status (1xx … 5xx).
  long[6] byClass;
  /// Count per latency bucket (not cumulative); last = above the last bound.
  long[] latency;
  double totalMilliseconds = 0;
  AreaStats[] areas;
  /// Requests per minute, oldest first (the last entry is the current minute).
  long[] perMinute;
  RequestSample[] recent;
  RequestSample[] failures;
  RequestSample[] slow;

  double averageMilliseconds() const pure nothrow {
    return requests ? totalMilliseconds / requests : 0;
  }

  /// Approximate percentile (upper bound of the bucket holding it), in ms.
  double percentile(double p) const pure nothrow {
    long total;
    foreach (n; latency)
      total += n;
    if (total == 0)
      return 0;
    auto rank = cast(long)(p * total + 0.5);
    long seen;
    foreach (i, n; latency) {
      seen += n;
      if (seen >= rank && n > 0)
        return i < latencyBuckets.length ? latencyBuckets[i] : double.infinity;
    }
    return double.infinity;
  }

  /// Share of requests answered with 5xx.
  double errorRate() const pure nothrow {
    return requests ? cast(double) byClass[5] / requests : 0;
  }
}

/// Request metrics since the start. vibe.d runs the platform in one thread,
/// so no locking is needed.
class RequestMetrics {
  private {
    SysTime started;
    MonoTime startedMono;
    long total, current;
    long[6] classes;
    long[] buckets;
    double totalMs = 0;
    AreaStats[string] byArea;
    long[60] minutes_;
    long minuteOfLast = -1;
    RequestSample[] recent, failures, slow;
    size_t keep;
    double slowMs;
  }

  /// `keep` samples per list; requests from `slowMilliseconds` on count as slow.
  this(size_t keep = 50, double slowMilliseconds = 1000) {
    started = Clock.currTime(UTC());
    startedMono = MonoTime.currTime;
    buckets = new long[latencyBuckets.length + 1];
    this.keep = keep;
    slowMs = slowMilliseconds;
  }

  void begin() nothrow {
    current++;
  }

  void finish(RequestSample sample) nothrow {
    current = max(0, current - 1);
    total++;
    auto cls = sample.status / 100;
    classes[cls >= 1 && cls <= 5 ? cls : 0]++;
    totalMs += sample.milliseconds;
    size_t b;
    while (b < latencyBuckets.length && sample.milliseconds > latencyBuckets[b])
      b++;
    buckets[b]++;

    auto stats = sample.area in byArea;
    if (stats is null) {
      byArea[sample.area] = AreaStats(sample.area);
      stats = sample.area in byArea;
    }
    stats.requests++;
    if (sample.status >= 500)
      stats.serverErrors++;
    else if (sample.status >= 400)
      stats.clientErrors++;
    stats.totalMilliseconds += sample.milliseconds;
    stats.maxMilliseconds = max(stats.maxMilliseconds, sample.milliseconds);

    tick();
    minutes_[minuteOfLast % 60]++;

    push(recent, sample);
    if (sample.status >= 500)
      push(failures, sample);
    if (sample.milliseconds >= slowMs)
      push(slow, sample);
  }

  MetricsSnapshot snapshot() {
    tick();
    MetricsSnapshot s;
    s.startedAt = started;
    s.uptime = MonoTime.currTime - startedMono;
    s.requests = total;
    s.inFlight = current;
    s.byClass = classes;
    s.latency = buckets.dup;
    s.totalMilliseconds = totalMs;
    s.areas = byArea.values;
    s.areas.sort!((a, b) => a.requests > b.requests);
    foreach (i; 0 .. 60) {
      auto m = minuteOfLast - 59 + i;
      s.perMinute ~= m < 0 ? 0 : minutes_[m % 60];
    }
    s.recent = newestFirst(recent);
    s.failures = newestFirst(failures);
    s.slow = newestFirst(slow);
    return s;
  }

  /// Advance the per-minute ring to the current minute, clearing skipped ones.
  private void tick() nothrow {
    auto now = (MonoTime.currTime - startedMono).total!"minutes";
    if (minuteOfLast < 0)
      minuteOfLast = 0;
    while (minuteOfLast < now) {
      minuteOfLast++;
      minutes_[minuteOfLast % 60] = 0;
    }
  }

  private void push(ref RequestSample[] list, RequestSample sample) nothrow {
    list ~= sample;
    if (list.length > keep)
      list = list[$ - keep .. $].dup;
  }

  private static RequestSample[] newestFirst(const(RequestSample)[] list) {
    RequestSample[] r;
    foreach_reverse (s; list)
      r ~= s;
    return r;
  }
}

/// The area of a request path, for per-area figures (bounded cardinality).
string areaOf(string path, string restPath, string odataPath) pure nothrow {
  import std.algorithm : startsWith;

  if (path == "/")
    return "site";
  if (path.startsWith("/media/"))
    return "media";
  if (path.startsWith("/ui/"))
    return "assets";
  if (path.startsWith(restPath))
    return "rest";
  if (path.startsWith(odataPath))
    return "odata";
  if (path.startsWith("/api/") || path == "/health" || path == "/metrics")
    return "api";
  foreach (prefix; ["/files", "/sites", "/users", "/roles", "/status", "/monitoring", "/account", "/login", "/logout", "/start"])
    if (path == prefix || path.startsWith(prefix ~ "/"))
      return prefix[1 .. $];
  return "other";
}

// ── log ──────────────────────────────────────────────────────────────────

struct LogEntry {
  SysTime at;
  LogLevel level;
  string text;

  string levelName() const pure nothrow {
    switch (level) {
    case LogLevel.trace, LogLevel.debugV, LogLevel.debug_:
      return "debug";
    case LogLevel.diagnostic, LogLevel.info:
      return "info";
    case LogLevel.warn:
      return "warn";
    default:
      return "error";
    }
  }
}

/// Keeps the last log lines (vibe.d logger; register with `registerLogger`).
class LogBuffer : Logger {
  private LogEntry[] entries;
  private size_t capacity;
  private long[LogLevel] counts;

  this(size_t capacity = 500, LogLevel level = LogLevel.info) {
    this.capacity = capacity;
    minLevel = level;
  }

  override void log(ref LogLine line) {
    entries ~= LogEntry(line.time, line.level, line.text.idup);
    if (entries.length > capacity + capacity / 4)
      entries = entries[$ - capacity .. $].dup;
    counts[line.level]++;
  }

  /// Newest first; `level` = minimum level; at most `limit` entries.
  LogEntry[] recent(LogLevel level = LogLevel.min, size_t limit = 200) @trusted {
    synchronized (this) {
      LogEntry[] r;
      foreach_reverse (e; entries)
        if (e.level >= level) {
          r ~= e;
          if (r.length >= limit)
            break;
        }
      return r;
    }
  }

  /// Lines logged since the start at `level` or above.
  long countFrom(LogLevel level) @trusted {
    synchronized (this) {
      long n;
      foreach (l, c; counts)
        if (l >= level)
          n += c;
      return n;
    }
  }
}

/// A log file per day: `<directory>/<prefix>-YYYY-MM-DD.<extension>`. Files
/// older than `retentionDays` are removed when the day changes.
class DailyLogFile {
  import std.stdio : File;

  private string directory, prefix, extension;
  private int retentionDays;
  private string day;
  private File file;

  this(string directory, string prefix, string extension, int retentionDays) {
    this.directory = directory;
    this.prefix = prefix;
    this.extension = extension;
    this.retentionDays = retentionDays;
  }

  string location() const {
    return directory;
  }

  /// Append one line (a newline is added).
  void writeLine(scope const(char)[] text, SysTime at) @trusted {
    import std.file : mkdirRecurse;
    import std.path : buildPath;

    auto today = at.toUTC.toISOExtString[0 .. 10];
    if (today != day || !file.isOpen) {
      if (file.isOpen)
        file.close();
      mkdirRecurse(directory);
      file = File(buildPath(directory, prefix ~ "-" ~ today ~ "." ~ extension), "a");
      day = today;
      cleanUp(at);
    }
    file.writeln(text);
    file.flush();
  }

  private void cleanUp(SysTime now) @trusted {
    import core.time : days;
    import std.file : dirEntries, remove, SpanMode;
    import std.path : baseName;

    if (retentionDays <= 0)
      return;
    auto oldest = (now.toUTC - retentionDays.days).toISOExtString[0 .. 10];
    try
      foreach (e; dirEntries(directory, prefix ~ "-*." ~ extension, SpanMode.shallow)) {
        auto name = e.name.baseName;
        auto date = name[prefix.length + 1 .. $ - extension.length - 1];
        if (date.length == 10 && date < oldest)
          remove(e.name);
      }
    catch (Exception) {
    }
  }
}

/// Writes the application log into daily files (`platform-YYYY-MM-DD.log`).
class FileLogWriter : Logger {
  private DailyLogFile file;

  this(DailyLogFile file, LogLevel level = LogLevel.info) {
    this.file = file;
    minLevel = level;
  }

  override void log(ref LogLine line) {
    try
      file.writeLine(format("%s [%s] %s", line.time.toUTC.toISOExtString, LogEntry(line.time, line.level).levelName,
          line.text), line.time);
    catch (Exception) {
    }
  }
}

/// Map a configured level name to vibe.d; unknown names → info.
LogLevel parseLogLevel(string level) pure nothrow {
  switch (level) {
  case "trace":
    return LogLevel.trace;
  case "debug":
    return LogLevel.debug_;
  case "warn":
    return LogLevel.warn;
  case "error":
    return LogLevel.error;
  default:
    return LogLevel.info;
  }
}

/// "3 d 4 h", "2 h 5 min", "42 s"
string uptimeText(Duration d) pure {
  auto s = d.total!"seconds";
  if (s >= 86_400)
    return format("%s d %s h", s / 86_400, s % 86_400 / 3600);
  if (s >= 3600)
    return format("%s h %s min", s / 3600, s % 3600 / 60);
  if (s >= 60)
    return format("%s min %s s", s / 60, s % 60);
  return format("%s s", s);
}

///
unittest {
  auto m = new RequestMetrics(2, 100);
  foreach (i, ms; [3.0, 40, 250, 7])
    m.finish(RequestSample(SysTime.init, "GET", "/x", i == 2 ? "files" : "pages", i == 2 ? 503 : 200, ms));
  m.begin();
  auto s = m.snapshot;
  assert(s.requests == 4 && s.byClass[2] == 3 && s.byClass[5] == 1 && s.inFlight == 1);
  assert(s.latency[0] == 1 && s.latency[1] == 1 && s.latency[3] == 1 && s.latency[5] == 1);
  assert(s.percentile(0.5) == 10 && s.percentile(1) == 250);
  assert(s.recent.length == 2 && s.recent[0].milliseconds == 7);
  assert(s.failures.length == 1 && s.slow.length == 1 && s.slow[0].area == "files");
  assert(s.areas[0].area == "pages" && s.areas[0].requests == 3);
  assert(s.perMinute.length == 60 && s.perMinute[$ - 1] == 4);
  assert(s.errorRate == 0.25);

  assert(areaOf("/", "/rest/v1/", "/odata/v4/platform") == "site");
  assert(areaOf("/files/abc/download", "/rest/v1/", "/odata") == "files");
  assert(areaOf("/filesx", "/rest/v1/", "/odata") == "other");
  assert(areaOf("/rest/v1/services", "/rest/v1/", "/odata") == "rest");
  assert(uptimeText(minutes(125)) == "2 h 5 min");
}

///
unittest {
  import std.file : exists, readText, rmdirRecurse, tempDir, write, mkdirRecurse;
  import std.path : buildPath;
  import std.uuid : randomUUID;
  import core.time : days;

  auto dir = buildPath(tempDir, "neko-logs-" ~ randomUUID.toString);
  scope (exit)
    () @trusted { if (dir.exists) rmdirRecurse(dir); }();
  auto now = SysTime.fromISOExtString("2026-11-20T08:00:00Z");
  () @trusted {
    mkdirRecurse(dir);
    write(buildPath(dir, "access-2026-10-01.ndjson"), "old");
    write(buildPath(dir, "access-2026-11-19.ndjson"), "recent");
  }();
  auto log = new DailyLogFile(dir, "access", "ndjson", 14);
  log.writeLine(`{"a":1}`, now);
  log.writeLine(`{"a":2}`, now);
  () @trusted {
    assert(readText(buildPath(dir, "access-2026-11-20.ndjson")) == "{\"a\":1}\n{\"a\":2}\n");
    assert(!buildPath(dir, "access-2026-10-01.ndjson").exists && buildPath(dir, "access-2026-11-19.ndjson").exists);
  }();
}
