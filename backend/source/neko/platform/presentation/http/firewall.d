/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The firewall in front of the router. In this order, for every request:
///
///   1. IP allow / deny lists (always enforced, whatever the mode)
///   2. bans (automatic after repeated findings, or set by an administrator)
///   3. rate limit per client address
///   4. inspection (WafInspector: protocol, traversal, scanners, SQLi, XSS, RCE)
///
/// Steps 2–4 follow `firewallMode`: "block" refuses, "detect" only logs and
/// counts. Addresses on an allow list are exempt from automatic bans and the
/// rate limit, but are still inspected.
module neko.platform.presentation.http.firewall;

import core.time : minutes;
import std.algorithm : canFind, startsWith;
import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.string : split, strip;
import vibe.core.log : logWarn;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse;
import vibe.textfilter.urlencode : urlDecode;
import neko.platform.domain.entities.iprule : RequestArea;
import neko.platform.domain.types.ipnetwork;
import neko.platform.infrastructure.firewall;
import neko.platform.infrastructure.monitoring.traffic;
import neko.platform.infrastructure.security : apiContentSecurityPolicy;
import neko.platform.ports.usecases : IManageNetworkUseCase;

@safe:

/// The address of the client: the peer, or — if the peer is a trusted
/// proxy — the last X-Forwarded-For entry that is not a trusted proxy.
class ClientAddresses {
  private IpNetwork[] proxies;

  this(const(string)[] trustedProxies) {
    foreach (p; trustedProxies)
      proxies ~= IpNetwork(p);
  }

  string of(scope HTTPServerRequest req) @trusted {
    if (auto cached = "neko.client" in req.context)
      return cached.get!string;
    auto address = resolve(req.clientAddress.toAddressString, req.headers.get("X-Forwarded-For", ""));
    req.context["neko.client"] = address;
    return address;
  }

  /// `peer` "" = unix socket.
  string resolve(string peer, string forwardedFor) {
    if (!trusted(peer) || forwardedFor.length == 0)
      return normalized(peer);
    auto hops = forwardedFor.split(",");
    foreach_reverse (hop; hops) {
      auto h = hop.strip;
      if (!trusted(h))
        return normalized(h);
    }
    return normalized(hops[0].strip);
  }

  private bool trusted(string address) {
    IpAddress a;
    if (!tryParseIpAddress(address, a))
      return false;
    foreach (p; proxies)
      if (p.contains(a))
        return true;
    return false;
  }

  private static string normalized(string address) {
    IpAddress a;
    return tryParseIpAddress(address, a) ? a.toString : "";
  }
}

/// The area of a path, for the IP lists.
RequestArea areaFor(string path, string restPath, string odataPath) pure nothrow {
  if (path == "/" || path.startsWith("/media/") || path.startsWith("/ui/") || path == "/health")
    return RequestArea.public_;
  if (path.startsWith(restPath) || path.startsWith(odataPath) || path.startsWith("/api/") || path == "/metrics")
    return RequestArea.api;
  return RequestArea.admin;
}

class Firewall : HTTPServerRequestHandler {
  private HTTPServerRequestHandler next;
  private ClientAddresses addresses;
  private IManageNetworkUseCase network;
  private WafInspector waf;
  private RateLimiter limiter;
  private BanList bans;
  private TrafficMonitor traffic;
  private FirewallMode mode_;
  private string restPath, odataPath;

  this(HTTPServerRequestHandler next, ClientAddresses addresses, IManageNetworkUseCase network, WafInspector waf,
      RateLimiter limiter, BanList bans, TrafficMonitor traffic, FirewallMode mode, string restPath, string odataPath) {
    this.next = next;
    this.addresses = addresses;
    this.network = network;
    this.waf = waf;
    this.limiter = limiter;
    this.bans = bans;
    this.traffic = traffic;
    this.mode_ = mode;
    this.restPath = restPath;
    this.odataPath = odataPath;
  }

  FirewallMode mode() const {
    return mode_;
  }

  void handleRequest(scope HTTPServerRequest req, scope HTTPServerResponse res) {
    auto client = addresses.of(req);
    auto path = req.requestPath.toString;
    auto area = areaFor(path, restPath, odataPath);
    auto now = Clock.currTime(UTC());
    auto method = req.method.to!string;

    // 1. IP lists
    auto decision = network.check(client, area);
    if (!decision.allowed) {
      record(now, client, "network", "iplist", method, path, decision.reason, true);
      return refuse(req, res, 403, "Access from your address is not allowed here (" ~ decision.reason ~ ").");
    }
    if (mode_ == FirewallMode.off)
      return next.handleRequest(req, res);
    auto allowlisted = network.isAllowlisted(client);
    auto enforce = mode_ == FirewallMode.block;

    // 2. bans
    Ban ban;
    if (bans.isBanned(client, now, ban) && (ban.manual || !allowlisted)) {
      record(now, client, "ban", "ban", method, path, "banned until " ~ ban.until.toISOExtString[0 .. 19] ~ "Z: "
          ~ ban.reason, enforce);
      if (enforce)
        return refuse(req, res, 403, "Your address is blocked until " ~ ban.until.toISOExtString[0 .. 10] ~ " "
            ~ ban.until.toISOExtString[11 .. 16] ~ " UTC" ~ (ban.manual ? "." : " after repeated suspicious requests."));
    }

    // 3. rate limit
    if (!allowlisted && !limiter.allow(client, now)) {
      record(now, client, "rate-limit", "rate-limit", method, path, "more than " ~ limiter.limit.to!string
          ~ " requests per minute", enforce);
      if (enforce) {
        res.headers["Retry-After"] = "60";
        return refuse(req, res, 429, "Too many requests from your address. Try again in a minute.");
      }
    }

    // 4. inspection
    WafFinding finding;
    if (waf.inspect(wafRequest(req, path), finding)) {
      record(now, client, "waf", finding.rule, method, path, finding.description ~ " (" ~ finding.where ~ ")", enforce);
      if (!allowlisted && bans.strike(client, now, finding.rule)) {
        logWarn("[firewall] banned %s after repeated findings (last: %s)", client, finding.rule);
        record(now, client, "ban", "ban", method, path, "automatic ban after repeated findings", enforce);
      }
      if (enforce)
        return refuse(req, res, 403, "The request was blocked by the web application firewall (rule "
            ~ finding.rule ~ ": " ~ finding.description ~ ").");
    }
    next.handleRequest(req, res);
  }

  private WafRequest wafRequest(scope HTTPServerRequest req, string path) @trusted {
    WafRequest r;
    r.method = req.method.to!string;
    r.uri = req.requestURI;
    try
      r.path = urlDecode(path);
    catch (Exception)
      r.path = path;
    r.userAgent = req.headers.get("User-Agent", "");
    foreach (k, v; req.query.byKeyValue)
      r.fields ~= [k, v];
    auto type = req.headers.get("Content-Type", "");
    // URL-encoded bodies only: multipart bodies are uploads
    if (type.startsWith("application/x-www-form-urlencoded"))
      foreach (k, v; req.form.byKeyValue)
        r.fields ~= [k, v];
    return r;
  }

  private void record(SysTime at, string client, string kind, string rule, string method, string path, string detail,
      bool blocked) nothrow {
    traffic.security(SecurityEvent(at, client, kind, rule, method, path.length > 200 ? path[0 .. 200] : path, detail,
        blocked));
    try
      logWarn("[firewall] %s %s %s %s from %s: %s", blocked ? "blocked" : "detected", rule, method, path,
        client.length ? client : "local", detail);
    catch (Exception) {
    }
  }

  private void refuse(scope HTTPServerRequest req, scope HTTPServerResponse res, int status, string message) {
    res.headers["Content-Security-Policy"] = apiContentSecurityPolicy;
    res.headers["X-Content-Type-Options"] = "nosniff";
    res.headers["X-Frame-Options"] = "DENY";
    res.headers["Cache-Control"] = "no-store";
    auto path = req.requestPath.toString;
    if (areaFor(path, restPath, odataPath) == RequestArea.api && path != "/metrics") {
      import vibe.data.json : Json;

      auto body = Json.emptyObject;
      body["error"] = Json(["code": Json(status == 429 ? "TooManyRequests" : "Forbidden"), "message": Json(message)]);
      res.writeJsonBody(body, status);
    } else
      res.writeBody(message, status, "text/plain; charset=utf-8");
  }
}

///
unittest {
  auto direct = new ClientAddresses(null);
  assert(direct.resolve("203.0.113.5", "1.2.3.4") == "203.0.113.5"); // untrusted peer: header ignored
  assert(direct.resolve("", "") == "" && direct.resolve("::ffff:10.0.0.1", "") == "10.0.0.1");
  auto proxied = new ClientAddresses(["10.0.0.0/8"]);
  assert(proxied.resolve("10.0.0.2", "198.51.100.7, 10.0.0.3") == "198.51.100.7");
  assert(proxied.resolve("10.0.0.2", "6.6.6.6, 198.51.100.7") == "198.51.100.7"); // spoofed first hop ignored
  assert(proxied.resolve("10.0.0.2", "") == "10.0.0.2" && proxied.resolve("10.0.0.2", "garbage") == "");

  assert(areaFor("/", "/rest/v1/", "/odata") == RequestArea.public_);
  assert(areaFor("/media/a/b", "/rest/v1/", "/odata") == RequestArea.public_);
  assert(areaFor("/rest/v1/services", "/rest/v1/", "/odata") == RequestArea.api);
  assert(areaFor("/metrics", "/rest/v1/", "/odata") == RequestArea.api);
  assert(areaFor("/login", "/rest/v1/", "/odata") == RequestArea.admin);
  assert(areaFor("/index.html", "/rest/v1/", "/odata") == RequestArea.admin);
}

/// The client address of a request as resolved by `ClientAddresses` (set by
/// the request monitor), else the peer address.
string clientAddressOf(scope HTTPServerRequest req) @trusted {
  if (auto cached = "neko.client" in req.context)
    return cached.get!string;
  return req.clientAddress.toAddressString;
}
