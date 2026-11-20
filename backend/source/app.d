/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Entry point. One executable per security domain (dub --config=open|restricted|confidential|secret);
/// the domain is fixed at compile time so a binary can never run in the wrong domain.
module app;

import core.time : minutes;
import std.array : join;
import vibe.core.core : runApplication;
import vibe.core.log : LogLevel, registerLogger;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, HTTPServerSettings, listenHTTP;
import neko.platform;

version (DomainOpen)
  enum selfDomain = SecurityDomain.open;
else version (DomainRestricted)
  enum selfDomain = SecurityDomain.restricted;
else version (DomainConfidential)
  enum selfDomain = SecurityDomain.confidential;
else version (DomainSecret)
  enum selfDomain = SecurityDomain.secret;
else
  static assert(0, "Set one of DomainOpen, DomainRestricted, DomainConfidential, or DomainSecret");

int main(string[] args) {
  auto config = loadConfig(selfDomain);
  try
    config.validate();
  catch (Exception e) {
    logError("Invalid configuration: %s", e.msg);
    return 2;
  }
  configureLogging(config.logLevel);
  auto container = buildContainer(config, selfDomain);

  if (args.length > 1 && args[1] != "serve") {
    setLogLevel(LogLevel.warn); // keep CLI output clean
    return runCli(container, args[1 .. $]);
  }
  return serve(container);
}

int serve(PlatformContainer c) {
  auto config = c.config;
  auto router = new URLRouter;

  // Logging and monitoring: the recent log for /monitoring, daily log files,
  // request metrics (and the access log) for every request.
  auto level = parseLogLevel(config.logLevel);
  auto logBuffer = new LogBuffer(500, level);
  registerLogger(cast(shared) logBuffer);
  auto logDir = config.effectiveLogDir(selfDomain);
  DailyLogFile accessFile;
  if (logDir.length) {
    registerLogger(cast(shared) new FileLogWriter(new DailyLogFile(logDir, "platform", "log", config.logRetentionDays),
      level));
    if (config.accessLog)
      accessFile = new DailyLogFile(logDir, "access", "ndjson", config.logRetentionDays);
  }
  auto metrics = new RequestMetrics;

  // Network security: client addresses (trusted proxies), traffic per
  // client, IP lists, bans, rate limit and the web application firewall
  // in front of the router; the request monitor in front of everything.
  auto addresses = new ClientAddresses(config.proxyList);
  auto traffic = new TrafficMonitor;
  auto bans = new BanList(config.banAfterViolations, config.banMinutes.minutes);
  auto firewall = new Firewall(router, addresses, c.network, new WafInspector,
    new RateLimiter(config.rateLimitPerMinute), bans, traffic, parseFirewallMode(config.firewallMode),
    config.restPath, config.odataPath);
  auto handler = new RequestMonitor(firewall, metrics, config.accessLog, accessFile, config.restPath,
    config.odataPath, addresses, traffic);

  // Order matters: middleware first, the static catch-all last.
  auto security = new SecurityMiddleware(config);
  security.registerRoutes(router);
  (new Health_Controller(config, selfDomain)).registerRoutes(router);
  router.get("/metrics", &(new MetricsController(metrics, logBuffer, c.events, c.files, config.metricsToken,
    selfDomain.label, traffic, bans)).handle);
  UnixSocketController socket;
  if (config.transport == "unix") {
    socket = new UnixSocketController(config.effectiveSocketPath(selfDomain));
    socket.registerRoutes(router);
  }
  router.registerPlatformRestApi(c.services, c.health, c.transfers, c.overview, config.restPath);
  new PlatformODataController(c.services, c.health, c.transfers, c.overview, config.odataPath).registerRoutes(router);

  // The public site at "/" (by host name, else the default site) and the
  // server-rendered pages with sign-in: vibe.d web interfaces with access
  // rights from roles; Tabler + htmx, assets embedded.
  bootstrapAdministrator(c);
  auto sessions = new WebSessions(c.passwords, c.clock, config.sessionIdleMinutes.minutes);
  auto guard = new WebGuard(sessions, c.authentication, config.serviceName, selfDomain.label);
  WebPages pages;
  pages.auth = new AuthWeb(guard, c.authentication, c.users, c.roles, new LoginThrottle(c.clock));
  pages.status = new StatusWeb(guard, c.overview, c.services, c.events);
  pages.monitoring = new MonitoringWeb(guard, metrics, logBuffer, c.events, c.files, logDir, config.accessLog);
  pages.security = new SecurityWeb(guard, c.network, traffic, bans, FirewallInfo(config.firewallMode,
    config.rateLimitPerMinute, config.banAfterViolations, config.banMinutes, config.trustedProxies), c.events);
  pages.sites = new SitesWeb(guard, c.sites);
  pages.files = new FilesWeb(guard, c.files, c.sites, config.maxUploadBytes);
  pages.users = new UsersWeb(guard, c.users, c.roles, c.sites);
  pages.roles = new RolesWeb(guard, c.roles);
  pages.site = new PublicSiteController(guard, c.sites, c.files);
  router.registerWebPages(pages);
  auto errorPages = webErrorPages(guard, (string path) @safe => security.isApi(path));

  // The Fiori app (/index.html, …): static catch-all, registered last.
  auto frontend = new FrontendController(config.frontendDir);
  frontend.registerRoutes(router);

  auto worker = new HealthCheckWorker(c.health, config.healthCheckIntervalSeconds);
  worker.start();

  logInfo("%s — domain %s (export=%s, import=%s), storage %s, files %s, logs %s, config from %s",
    config.serviceName, selfDomain.label, selfDomain.canExport, selfDomain.canImport, c.store.describe,
    c.blobs.describe, logDir.length ? logDir : "console only", config.sources.join(" → "));

  if (socket !is null) {
    socket.start(handler, errorPages, config.maxRequestBytes);
    scope (exit)
      socket.stop();
    logEndpoints(config, frontend);
    return runApplication();
  }

  auto settings = new HTTPServerSettings;
  settings.port = config.effectivePort(selfDomain);
  settings.bindAddresses = [config.host];
  settings.errorPageHandler = errorPages;
  settings.maxRequestSize = config.maxRequestBytes; // uploads
  auto listener = listenHTTP(settings, handler);
  scope (exit)
    listener.stopListening();
  logEndpoints(config, frontend);
  return runApplication();
}

/// The first web administrator, if this domain has no user account yet.
void bootstrapAdministrator(PlatformContainer c) {
  auto result = c.authentication.ensureAdministrator(c.config.adminUser, c.config.adminPassword);
  if (!result.created)
    return;
  if (result.generatedPassword.length > 0)
    logWarn("Created web administrator '%s' with the generated password '%s' — sign in at /login and change it "
        ~ "under Account (or set adminPassword / NEKO_ADMIN_PASSWORD before the first start)",
      result.userName, result.generatedPassword);
  else
    logInfo("Created web administrator '%s' with the configured adminPassword", result.userName);
}

void logEndpoints(PlatformConfig config, FrontendController frontend) {
  logInfo("  REST   %s{overview,services,transfers}", config.restPath);
  logInfo("  OData  %s/$metadata", config.odataPath);
  logInfo("  Site   / (default site, or the site claiming the host name), /media/* (public files)");
  logInfo("  Web    /login, /status, /monitoring, /security, /sites, /files, /users, /roles, /account (rights by role)");
  logInfo("  Guard  firewall %s, rate limit %s/min, IP rules in %s", config.firewallMode,
    config.rateLimitPerMinute, config.storage == "file" ? "iprules.json" : "memory");
  logInfo("  Ops    /health, /metrics (Prometheus), /api/v1/info%s", config.transport == "unix" ? ", /api/v1/socket" : "");
  if (frontend.available)
    logInfo("  Fiori  /index.html (%s)", frontend.location);
  else
    logInfo("  Fiori  not served (no frontend/index.html found; use the approuter or set frontendDir)");
}
