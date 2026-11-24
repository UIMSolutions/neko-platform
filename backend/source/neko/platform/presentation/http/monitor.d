/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Request monitoring: wraps the router, measures every request, writes the
/// access log, and serves GET /metrics in the Prometheus text format.
module neko.platform.presentation.http.monitor;

import core.time : MonoTime;
import std.algorithm : startsWith;
import std.array : appender;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.format : format, formattedWrite;
import vibe.core.log : logDebug, logInfo, logWarn;
import vibe.data.json : Json;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse;
import vibe.http.common : HTTPStatusException;
import neko.platform.infrastructure.monitoring;
import neko.platform.infrastructure.logging : LoggingEventPublisher;
import neko.platform.ports.usecases : IManageFilesUseCase;
import neko.platform.presentation.http.firewall : ClientAddresses, clientAddressOf;
import neko.platform.infrastructure.firewall : BanList;

@safe:

/// Put in front of the router: `listenHTTP(settings, new RequestMonitor(router, …))`.
class RequestMonitor : HTTPServerRequestHandler {
  private HTTPServerRequestHandler next;
  private RequestMetrics metrics;
  private DailyLogFile accessFile;
  private bool accessLog;
  private string restPath, odataPath;
  private ClientAddresses addresses;
  private TrafficMonitor traffic;
  private UsageCounter counter;

  /// Count billable requests per global account and subaccount (see
  /// `billedSubaccount`); each global account bills its own subaccounts.
  void meterUsage(UsageCounter counter) {
    this.counter = counter;
  }

  /// `accessFile` may be null (no access log file).
  this(HTTPServerRequestHandler next, RequestMetrics metrics, bool accessLog, DailyLogFile accessFile,
      string restPath, string odataPath, ClientAddresses addresses, TrafficMonitor traffic) {
    this.addresses = addresses;
    this.traffic = traffic;
    this.next = next;
    this.metrics = metrics;
    this.accessLog = accessLog;
    this.accessFile = accessFile;
    this.restPath = restPath;
    this.odataPath = odataPath;
  }

  void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    auto started = MonoTime.currTime;
    addresses.of(req); // resolved once; the firewall and the pages use it
    metrics.begin();
    int status;
    try {
      next.handleRequest(req, res);
      // Nothing written: vibe.d answers 404 after us.
      status = res.headerWritten ? res.statusCode : 404;
    } catch (HTTPStatusException e) {
      status = e.status;
      throw e;
    } catch (Exception e) {
      status = 500;
      throw e;
    } finally {
      flushBody(req, res, status);
      record(req, res, status, (MonoTime.currTime - started).total!"usecs" / 1000.0);
    }
  }

  private void record(scope HTTPServerRequest req, scope HTTPServerResponse res, int status, double ms) nothrow {
    try {
      auto path = req.requestPath.toString;
      auto area = areaOf(path, restPath, odataPath);
      auto client = clientAddressOf(req);
      auto sample = RequestSample(Clock.currTime(UTC()), req.method.to!string, path, area, status, ms, client);
      metrics.finish(sample);
      auto sent = responseBytes(req, res, status);
      traffic.record(client, sample.at, requestBytes(req), sent, status, req.headers.get("User-Agent", ""), path);
      if (counter !is null && status < 400) {
        auto sub = billedSubaccount(area, path, contextText(req, "neko.subaccount"),
          contextText(req, "neko.callSource"));
        if (sub.length)
          counter(contextText(req, "neko.globalAccount"), sub, sample.at, sent);
      }
      if (!accessLog)
        return;
      // Assets and probes only at debug level: they would drown the log.
      if (area == "assets" || path == "/health" || path == "/metrics")
        logDebug("[http] %s %s %s %.1f ms", sample.method, path, status, ms);
      else if (status >= 500)
        logWarn("[http] %s %s %s %.1f ms (%s)", sample.method, path, status, ms, client);
      else
        logInfo("[http] %s %s %s %.1f ms", sample.method, path, status, ms);
      if (accessFile !is null) {
        auto j = Json.emptyObject;
        j["time"] = sample.at.toISOExtString;
        j["method"] = sample.method;
        j["path"] = path; // without the query: it may carry personal data
        j["status"] = status;
        j["ms"] = cast(double)(cast(long)(ms * 10)) / 10;
        j["area"] = area;
        j["client"] = client;
        j["host"] = req.host;
        auto account = contextText(req, "neko.globalAccount"), tenant = contextText(req, "neko.tenant");
        if (account.length)
          j["globalAccount"] = account;
        if (tenant.length)
          j["tenant"] = contextText(req, "neko.subaccount") ~ "/" ~ tenant ~ "/" ~ contextText(req, "neko.space");
        accessFile.writeLine(j.toString, sample.at);
      }
    } catch (Exception) {
    }
  }
}

/// Counts a billable request of a global account (key, subaccount, time, bytes sent).
alias UsageCounter = void delegate(string globalAccount, string subaccount, SysTime at, long bytes) @safe;

/// The subaccount a request is billed to, "" for none:
///   /media/<subaccount>/…   public files, by their path
///   REST and OData          the subaccount of the call context, when the
///                           call named it (header or subdomain); calls that
///                           fell back to the first subaccount are not billed
string billedSubaccount(string area, string path, string subaccount, string source) pure nothrow {
  import std.string : indexOf;

  if (area == "media" && path.length > 7) {
    auto rest = path[7 .. $];
    auto slash = rest.indexOf('/');
    return slash > 0 ? rest[0 .. slash] : rest;
  }
  if ((area == "rest" || area == "odata") && source.length && source != "default")
    return subaccount;
  return "";
}

///
unittest {
  assert(billedSubaccount("media", "/media/shop-prod/f1/a.png", "", "") == "shop-prod");
  assert(billedSubaccount("rest", "/rest/v1/services", "shop-prod", "header") == "shop-prod");
  assert(billedSubaccount("odata", "/odata/v4/x", "shop-prod", "subdomain") == "shop-prod");
  assert(billedSubaccount("rest", "/rest/v1/services", "platform-open", "default") == "");
  assert(billedSubaccount("home", "/", "platform-open", "header") == "");
  assert(billedSubaccount("files", "/files", "shop-prod", "header") == "");
}

private string contextText(scope HTTPServerRequest req, string key) @trusted nothrow {
  try
    if (auto v = key in req.context)
      if (v.convertsTo!string)
        return v.get!string;
  catch (Exception) {
  }
  return "";
}

/// vibe.d sends the last buffered part of a streamed (chunked) body only
/// after the handler returns, so `bytesWritten` would miss it — all of a
/// small page. Flush it now: the same bytes, a little earlier. Only chunked
/// bodies (rendered pages) are flushed; they always have a body writer.
/// Bodies with Content-Length (files, writeBody) are counted by that header,
/// and void bodies (HEAD, 204, 304) are never touched.
private void flushBody(scope HTTPServerRequest req, scope HTTPServerResponse res, int status) nothrow {
  import vibe.http.common : HTTPMethod;

  try {
    if (res.headerWritten && req.method != HTTPMethod.HEAD && (status == 200 || status == 201)
        && "Content-Length" !in res.headers && res.headers.get("Transfer-Encoding", "") == "chunked")
      res.bodyWriter.flush();
  } catch (Exception) {
  }
}

/// Bytes of the response body sent (or about to be sent) for this request.
private long responseBytes(scope HTTPServerRequest req, scope HTTPServerResponse res, int status) nothrow {
  import vibe.http.common : HTTPMethod;

  long n;
  try {
    n = cast(long) res.bytesWritten;
    if (req.method != HTTPMethod.HEAD && status != 204 && status != 304)
      if (auto length = "Content-Length" in res.headers) {
        auto declared = (*length).to!long;
        if (declared > n)
          n = declared;
      }
  } catch (Exception) {
  }
  return n;
}

/// Approximate size of a request: request line, headers and the declared body.
private long requestBytes(scope HTTPServerRequest req) @trusted {
  long n = req.requestURI.length + 16;
  foreach (k, v; req.headers.byKeyValue)
    n += k.length + v.length + 4;
  try
    n += req.headers.get("Content-Length", "0").to!long;
  catch (Exception) {
  }
  return n;
}

/// GET /metrics. Without a token only local scrapers are served.
class MetricsController {
  private RequestMetrics metrics;
  private LogBuffer log;
  private LoggingEventPublisher events;
  private IManageFilesUseCase files;
  private string token;
  private string domain;
  private TrafficMonitor traffic;
  private BanList bans;

  this(RequestMetrics metrics, LogBuffer log, LoggingEventPublisher events, IManageFilesUseCase files, string token,
      string domain, TrafficMonitor traffic, BanList bans) {
    this.traffic = traffic;
    this.bans = bans;
    this.metrics = metrics;
    this.log = log;
    this.events = events;
    this.files = files;
    this.token = token;
    this.domain = domain;
  }

  void handle(HTTPServerRequest req, HTTPServerResponse res) {
    res.headers["Cache-Control"] = "no-store";
    if (!allowed(req)) {
      res.headers["WWW-Authenticate"] = `Bearer realm="metrics"`;
      res.writeBody("metrics: send the configured bearer token (metricsToken)\n", 401, "text/plain; charset=utf-8");
      return;
    }
    res.writeBody(prometheusText(metrics.snapshot, log, events, files, domain)
        ~ networkText(traffic.snapshot(0), bans.active(Clock.currTime(UTC())).length, domain),
      "text/plain; version=0.0.4; charset=utf-8");
  }

  private bool allowed(scope HTTPServerRequest req) {
    import neko.platform.presentation.web.sessions : sameText;

    if (token.length > 0)
      return sameText(req.headers.get("Authorization", ""), "Bearer " ~ token);
    auto client = req.clientAddress.toAddressString; // the peer, never a forwarded address
    // unix socket clients have no address; loopback over TCP
    return client.length == 0 || client.startsWith("127.") || client == "::1" || client.startsWith("::ffff:127.");
  }
}

/// The Prometheus exposition of the platform figures.
string prometheusText(const MetricsSnapshot s, LogBuffer log, LoggingEventPublisher events, IManageFilesUseCase files,
    string domain) {
  import vibe.core.log : LogLevel;

  auto o = appender!string;
  auto l = `domain="` ~ domain ~ `"`;
  void metric(string name, string type, string help) {
    o.formattedWrite("# HELP %s %s\n# TYPE %s %s\n", name, help, name, type);
  }

  metric("neko_uptime_seconds", "gauge", "Seconds since the start");
  o.formattedWrite("neko_uptime_seconds{%s} %s\n", l, s.uptime.total!"seconds");
  metric("neko_http_requests_in_flight", "gauge", "Requests being processed");
  o.formattedWrite("neko_http_requests_in_flight{%s} %s\n", l, s.inFlight);

  metric("neko_http_requests_total", "counter", "Finished HTTP requests by area and status class");
  foreach (a; s.areas)
    o.formattedWrite("neko_http_requests_total{%s,area=\"%s\",class=\"ok\"} %s\n", l, a.area,
      a.requests - a.clientErrors - a.serverErrors);
  foreach (a; s.areas) {
    o.formattedWrite("neko_http_requests_total{%s,area=\"%s\",class=\"4xx\"} %s\n", l, a.area, a.clientErrors);
    o.formattedWrite("neko_http_requests_total{%s,area=\"%s\",class=\"5xx\"} %s\n", l, a.area, a.serverErrors);
  }

  metric("neko_http_request_duration_seconds", "histogram", "Duration of HTTP requests");
  long cumulative;
  foreach (i, n; s.latency) {
    cumulative += n;
    auto le = i < latencyBuckets.length ? format("%g", latencyBuckets[i] / 1000) : "+Inf";
    o.formattedWrite("neko_http_request_duration_seconds_bucket{%s,le=\"%s\"} %s\n", l, le, cumulative);
  }
  o.formattedWrite("neko_http_request_duration_seconds_sum{%s} %.6f\n", l, s.totalMilliseconds / 1000);
  o.formattedWrite("neko_http_request_duration_seconds_count{%s} %s\n", l, s.requests);

  metric("neko_log_lines_total", "counter", "Log lines since the start by level");
  o.formattedWrite("neko_log_lines_total{%s,level=\"warn\"} %s\n", l,
    log.countFrom(LogLevel.warn) - log.countFrom(LogLevel.error));
  o.formattedWrite("neko_log_lines_total{%s,level=\"error\"} %s\n", l, log.countFrom(LogLevel.error));

  metric("neko_events_total", "counter", "Platform events since the start by type");
  foreach (type, n; events.countsByType)
    o.formattedWrite("neko_events_total{%s,type=\"%s\"} %s\n", l, type, n);

  auto storage = files.storage;
  metric("neko_subaccount_files", "gauge", "Files per subaccount");
  foreach (u; storage.subaccounts)
    o.formattedWrite("neko_subaccount_files{%s,subaccount=\"%s\"} %s\n", l, u.subaccount, u.files);
  metric("neko_subaccount_file_bytes", "gauge", "Bytes of the files per subaccount");
  foreach (u; storage.subaccounts)
    o.formattedWrite("neko_subaccount_file_bytes{%s,subaccount=\"%s\"} %s\n", l, u.subaccount, u.bytes);
  if (storage.available >= 0) {
    metric("neko_storage_available_bytes", "gauge", "Free bytes on the storage volume");
    o.formattedWrite("neko_storage_available_bytes{%s} %s\n", l, storage.available);
  }
  return o.data;
}

/// Prometheus figures of the network traffic and the firewall.
string networkText(const TrafficSnapshot t, size_t activeBans, string domain) {
  auto o = appender!string;
  auto l = `domain="` ~ domain ~ `"`;
  o.formattedWrite("# HELP neko_network_bytes_total Bytes since the start (in: requests, out: response bodies)\n"
      ~ "# TYPE neko_network_bytes_total counter\n");
  o.formattedWrite("neko_network_bytes_total{%s,direction=\"in\"} %s\n", l, t.bytesIn);
  o.formattedWrite("neko_network_bytes_total{%s,direction=\"out\"} %s\n", l, t.bytesOut);
  o.formattedWrite("# HELP neko_network_clients Distinct client addresses seen\n# TYPE neko_network_clients gauge\n");
  o.formattedWrite("neko_network_clients{%s} %s\n", l, t.clients);
  o.formattedWrite("# HELP neko_firewall_events_total Firewall findings by rule\n# TYPE neko_firewall_events_total counter\n");
  foreach (rule, n; t.byRule)
    o.formattedWrite("neko_firewall_events_total{%s,rule=\"%s\"} %s\n", l, rule, n);
  o.formattedWrite("# HELP neko_firewall_blocked_total Requests refused by the firewall\n"
      ~ "# TYPE neko_firewall_blocked_total counter\n");
  o.formattedWrite("neko_firewall_blocked_total{%s} %s\n", l, t.blocked);
  o.formattedWrite("# HELP neko_firewall_bans Addresses banned right now\n# TYPE neko_firewall_bans gauge\n");
  o.formattedWrite("neko_firewall_bans{%s} %s\n", l, activeBans);
  return o.data;
}
