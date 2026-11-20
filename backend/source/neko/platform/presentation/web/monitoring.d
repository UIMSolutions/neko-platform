/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Monitoring page (web interface): request figures, failures, the recent
/// log, storage and runtime. The live part refreshes itself every 10 s.
///
///   GET /monitoring?level=        page          monitoring.read
///   GET /monitoring/live?level=   live part     monitoring.read
///
/// The same figures for Prometheus: GET /metrics (presentation.http.monitor).
module neko.platform.presentation.web.monitoring;

import core.memory : GC;
import vibe.core.log : LogLevel;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : StorageDto;
import neko.platform.infrastructure.logging : LoggingEventPublisher;
import neko.platform.infrastructure.monitoring;
import neko.platform.ports.usecases : IManageFilesUseCase;
import neko.platform.presentation.web.guard;

@safe:

/// Runtime figures of the process.
struct RuntimeInfo {
  size_t heapUsed;
  size_t heapFree;
  string logLocation;
  bool accessLog;
}

@requiresAuth
class MonitoringWeb {
  private WebGuard guard;
  private RequestMetrics metrics;
  private LogBuffer log;
  private LoggingEventPublisher events;
  private IManageFilesUseCase files;
  private string logLocation;
  private bool accessLog;

  mixin PageAuthentication;

  this(WebGuard guard, RequestMetrics metrics, LogBuffer log, LoggingEventPublisher events, IManageFilesUseCase files,
      string logLocation, bool accessLog) {
    this.guard = guard;
    this.metrics = metrics;
    this.log = log;
    this.events = events;
    this.files = files;
    this.logLocation = logLocation;
    this.accessLog = accessLog;
  }

  @auth(Role.monitoringRead) @path("/monitoring")
  void getMonitoring(PageContext page, string level = "info") {
    page = page.at("Monitoring", "monitoring");
    live(page, level, "monitoring.dt");
  }

  @auth(Role.monitoringRead) @path("/monitoring/live")
  void getMonitoringLive(PageContext page, string level = "info") {
    page = page.at("Monitoring", "monitoring");
    live(page, level, "monitoring_live.dt");
  }

  @noRoute void live(PageContext page, string level, string which) {
    auto stats = metrics.snapshot;
    auto filter = level == "warn" || level == "error" || level == "debug" ? level : "info";
    auto lines = log.recent(parseLogLevel(filter), 150);
    auto warnings = log.countFrom(LogLevel.warn) - log.countFrom(LogLevel.error);
    auto errors = log.countFrom(LogLevel.error);
    auto eventCounts = events.countsByType;
    auto storage = files.storage;
    auto gc = (() @trusted => GC.stats)();
    auto runtime = RuntimeInfo(gc.usedSize, gc.freeSize, logLocation, accessLog);
    if (which == "monitoring.dt")
      render!("monitoring.dt", page, stats, filter, lines, warnings, errors, eventCounts, storage, runtime);
    else
      render!("monitoring_live.dt", page, stats, filter, lines, warnings, errors, eventCounts, storage, runtime);
  }
}

/// Requests per minute as an inline SVG bar chart (see `barChart`).
string requestBars(const(long)[] perMinute) pure {
  return barChart(perMinute, "Requests per minute", "request", "requests", false);
}

/// Per-minute values as an inline SVG bar chart (one series, newest right):
/// thin bars with rounded tops on a baseline, a tooltip per bar. `bytes`
/// formats values as sizes.
string barChart(const(long)[] perMinute, string title, string one, string many, bool bytes) pure {
  import neko.platform.application.dtos : byteSize;

  import std.algorithm : maxElement;
  import std.conv : to;
  import std.format : format;

  enum width = 600.0, height = 120.0, gap = 2.0;
  auto n = perMinute.length;
  if (n == 0)
    return "";
  auto peak = perMinute.maxElement;
  auto bar = width / n - gap;
  string svg = format(`<svg class="request-chart" viewBox="0 0 %s %s" preserveAspectRatio="none" role="img" `
      ~ `aria-label="%s, last %s minutes, peak %s">`, width, height + 1, title, n, bytes ? byteSize(peak) : peak.to!string);
  svg ~= format(`<line class="baseline" x1="0" x2="%s" y1="%s" y2="%s"/>`, width, height, height);
  foreach (i, v; perMinute) {
    auto x = i * (bar + gap) + gap / 2;
    auto ago = n - 1 - i;
    auto amount = bytes ? byteSize(v) : format("%s %s", v, v == 1 ? one : many);
    auto label = format("%s %s", amount, ago == 0 ? "this minute" : format("%s min ago", ago));
    // the full column is the hover target; the visible bar starts at the baseline
    svg ~= format(`<g><title>%s</title><rect class="hit" x="%.1f" y="0" width="%.1f" height="%s"/>`, label, x, bar + gap,
      height);
    if (v > 0) {
      auto h = peak ? (v * (height - 4)) / peak : 0;
      if (h < 2)
        h = 2;
      auto r = h < 4 ? h / 2 : 4.0;
      if (r > bar / 2)
        r = bar / 2;
      auto top = height - h;
      svg ~= format(`<path class="bar" d="M%.1f %.1fV%.1fq0 -%.1f %.1f -%.1fh%.1fq%.1f 0 %.1f %.1fV%.1fz"/>`,
        x, height, top + r, r, r, r, bar - 2 * r, r, r, r, height);
    }
    svg ~= "</g>";
  }
  return svg ~ "</svg>";
}

///
unittest {
  import std.algorithm : canFind, count;

  auto svg = requestBars([0, 3, 1]);
  assert(svg.canFind("<svg") && svg.count("<path") == 2 && svg.canFind("1 request this minute"));
  assert(requestBars(null) == "");
  assert(barChart([0, 2048], "Bytes in", "", "", true).canFind("2.0 KB this minute"));
}
