/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Entry point. One executable per security domain (dub --config=open|restricted|confidential|secret);
/// the domain is fixed at compile time so a binary can never run in the wrong domain.
module app;

import core.time : minutes, seconds;
import std.datetime.systime : SysTime;
import std.array : join;
import vibe.core.core : runApplication, setTimer;
import vibe.core.log : LogLevel, registerLogger;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerRequestHandler, HTTPServerResponse, HTTPServerSettings,
  listenHTTP;
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
  auto instance = buildInstance(config, selfDomain);

  if (args.length > 1 && args[1] != "serve") {
    setLogLevel(LogLevel.warn); // keep CLI output clean
    return runCli(instance, args[1 .. $]);
  }
  return serve(instance);
}

/// What one global account serves: its own router (pages, REST, OData,
/// public files) on its own container, sessions and usage meter.
final class AccountApp {
  PlatformContainer c;
  URLRouter router;
  WebGuard guard;
  UsageMeter meter;
  HealthCheckWorker worker;
}

/// Shared by all global accounts: the instance-level parts.
struct InstanceParts {
  PlatformInstance instance;
  RequestMetrics metrics;
  LogBuffer logBuffer;
  string logDir;
  TrafficMonitor traffic;
  BanList bans;
  SecurityMiddleware security;
  UnixSocketController socket;
}

int serve(PlatformInstance instance) {
  auto def = instance.defaultContainer();
  auto config = instance.config;

  // Logging and monitoring: the recent log for /monitoring, daily log files,
  // request metrics (and the access log) for every request.
  InstanceParts parts;
  parts.instance = instance;
  auto level = parseLogLevel(config.logLevel);
  parts.logBuffer = new LogBuffer(500, level);
  registerLogger(cast(shared) parts.logBuffer);
  parts.logDir = config.effectiveLogDir(selfDomain);
  DailyLogFile accessFile;
  if (parts.logDir.length) {
    registerLogger(cast(shared) new FileLogWriter(new DailyLogFile(parts.logDir, "platform", "log",
      config.logRetentionDays), level));
    if (config.accessLog)
      accessFile = new DailyLogFile(parts.logDir, "access", "ndjson", config.logRetentionDays);
  }
  parts.metrics = new RequestMetrics;
  parts.security = new SecurityMiddleware(config);
  if (config.transport == "unix")
    parts.socket = new UnixSocketController(config.effectiveSocketPath(selfDomain));

  // Global accounts are physically separate: each gets its own router on its
  // own container, built on its first request. The dispatcher picks the
  // global account of a request (host name, X-Neko-Global-Account, default).
  AccountApp[string] apps;
  AccountApp appOf(string key) @safe {
    if (auto s = key in apps)
      return *s;
    auto app = buildAccountApp(parts, instance.container(key));
    apps[key] = app;
    return app;
  }

  auto dispatcher = new GlobalAccountDispatcher(instance.accounts, (string key) @safe => cast(HTTPServerRequestHandler)
    appOf(key).router);

  // Network security: client addresses (trusted proxies), traffic per
  // client, IP lists (of the default global account: the operator's), bans,
  // rate limit and the web application firewall in front of the
  // dispatcher; the request monitor in front of everything.
  auto addresses = new ClientAddresses(config.proxyList);
  parts.traffic = new TrafficMonitor;
  parts.bans = new BanList(config.banAfterViolations, config.banMinutes.minutes);
  auto firewall = new Firewall(dispatcher, addresses, def.network, new WafInspector,
    new RateLimiter(config.rateLimitPerMinute), parts.bans, parts.traffic, parseFirewallMode(config.firewallMode),
    config.restPath, config.odataPath);
  auto handler = new RequestMonitor(firewall, parts.metrics, config.accessLog, accessFile, config.restPath,
    config.odataPath, addresses, parts.traffic);

  // Billing: requests and bytes per subaccount of each global account
  // (billedSubaccount), written every minute with the storage peak of each
  // subaccount (and once more at shutdown) into that global account's own
  // usage records.
  handler.meterUsage((string account, string subaccount, SysTime at, long bytes) @safe {
    if (auto s = account in apps)
      s.meter.count(subaccount, at, bytes);
  });
  void flushUsage() nothrow {
    foreach (key, s; apps)
      try
        s.c.usageRepository.add(s.meter.drain() ~ storagePeaks(s.c));
      catch (Exception e)
        logWarn("usage: cannot store usage records of %s: %s", key, e.msg);
  }

  auto usageTimer = setTimer(60.seconds, &flushUsage, true);
  scope (exit) {
    usageTimer.stop();
    flushUsage();
  }

  // The default global account answers from the start (and its error pages
  // serve everyone); the others on their first request.
  auto main = appOf(def.account.key);
  foreach (e; instance.accounts.list())
    if (!e.isDefault)
      appOf(e.key);
  auto errorPages = webErrorPages(main.guard, (string path) @safe => parts.security.isApi(path));

  logInfo("%s — domain %s (export=%s, import=%s), %s global account(s), storage %s, files %s, logs %s, config from %s",
    config.serviceName, selfDomain.label, selfDomain.canExport, selfDomain.canImport, instance.accounts.list().length,
    def.store.describe, def.blobs.describe, parts.logDir.length ? parts.logDir : "console only",
    config.sources.join(" → "));
  foreach (e; instance.accounts.list())
    logInfo("  Global account %s%s — hosts %s, data %s", e.key, e.isDefault ? " (default)" : "",
      e.hosts.length ? e.hosts.join(", ") : e.isDefault ? "*" : "none (X-Neko-Global-Account)",
      accountDataDir(config, selfDomain, e));

  auto frontend = new FrontendController(config.frontendDir);
  if (parts.socket !is null) {
    parts.socket.start(handler, errorPages, config.maxRequestBytes);
    scope (exit)
      parts.socket.stop();
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

/// The router of one global account on its container.
AccountApp buildAccountApp(ref InstanceParts parts, PlatformContainer c) @safe {
  auto config = c.config;
  auto app = new AccountApp;
  app.c = c;
  app.router = new URLRouter;
  auto router = app.router;
  app.meter = new UsageMeter;
  auto key = c.account.isDefault ? "" : c.account.key;

  // Order matters: middleware first, the static catch-all last.
  parts.security.registerRoutes(router);
  // The tenant, space and region of every service call (headers, host name).
  new CallContextMiddleware(c.landscape, c.account.key, config.restPath, config.odataPath).registerRoutes(router);
  (new Health_Controller(config, selfDomain)).registerRoutes(router);
  router.get("/metrics", &(new MetricsController(parts.metrics, parts.logBuffer, c.events, c.files, config.metricsToken,
    selfDomain.label, parts.traffic, parts.bans)).handle);
  if (parts.socket !is null)
    parts.socket.registerRoutes(router);
  router.registerPlatformRestApi(c.services, c.health, c.transfers, c.overview, config.restPath);
  new PlatformODataController(c.services, c.health, c.transfers, c.overview, config.odataPath).registerRoutes(router);

  // "/" (to the pages), public files at /media/* and the server-rendered
  // pages with sign-in: vibe.d web interfaces with access
  // rights from roles and from the account model (global account and
  // subaccount administrators); Tabler + htmx, assets embedded.
  bootstrapAdministrator(c);
  auto sessions = new WebSessions(c.passwords, c.clock, config.sessionIdleMinutes.minutes);
  auto guard = new WebGuard(sessions, c.authentication, c.account.isDefault ? config.serviceName
    : c.account.name ~ " · " ~ config.serviceName, selfDomain.label, key);
  auto landscape = c.landscape;
  guard.grants = (string user) @safe => landscape.grantedRights(user);
  app.guard = guard;
  WebPages pages;
  pages.auth = new AuthWeb(guard, c.authentication, c.users, c.roles, new LoginThrottle(c.clock));
  pages.status = new StatusWeb(guard, c.overview, c.services, c.events);
  pages.monitoring = new MonitoringWeb(guard, parts.metrics, parts.logBuffer, c.events, c.files, parts.logDir,
    config.accessLog);
  pages.security = new SecurityWeb(guard, c.network, parts.traffic, parts.bans, FirewallInfo(config.firewallMode,
    config.rateLimitPerMinute, config.banAfterViolations, config.banMinutes, config.trustedProxies), c.events);
  pages.landscape = new LandscapeWeb(guard, c.landscape, c.billing);
  pages.files = new FilesWeb(guard, c.files, config.maxUploadBytes);
  pages.users = new UsersWeb(guard, c.users, c.roles);
  pages.roles = new RolesWeb(guard, c.roles);
  pages.home = new HomeController(guard, c.files);
  if (c.account.isDefault) {
    auto instance = parts.instance;
    pages.accounts = new GlobalAccountsWeb(guard, instance.accounts, (GlobalAccountEntry e) @safe =>
        setUpAccount(instance.container(e.key)));
  }
  router.registerWebPages(pages);

  // The Fiori app (/index.html, …): static catch-all, registered last.
  new FrontendController(config.frontendDir).registerRoutes(router);

  app.worker = new HealthCheckWorker(c.health, config.healthCheckIntervalSeconds);
  app.worker.start();
  return app;
}

/// A new global account: its first administrator. Returns a note for the operator.
string setUpAccount(PlatformContainer c) @safe {
  auto result = c.authentication.ensureAdministrator(c.config.adminUser, c.config.adminPassword);
  if (!result.created)
    return "";
  if (result.generatedPassword.length)
    return "Administrator '" ~ result.userName ~ "' of " ~ c.account.key ~ " has the generated password '"
      ~ result.generatedPassword ~ "' — note it now, it is not shown again.";
  return "Administrator '" ~ result.userName ~ "' of " ~ c.account.key ~ " uses the configured adminPassword.";
}

/// The current file storage of each subaccount, as usage records (the
/// repository keeps the peak of the month).
UsageRecord[] storagePeaks(PlatformContainer c) {
  import std.datetime.systime : Clock;

  auto month = monthOf(Clock.currTime);
  UsageRecord[] list;
  foreach (u; c.files.storage().subaccounts)
    if (u.bytes > 0)
      list ~= UsageRecord(month, u.subaccount, 0, 0, u.bytes);
  return list;
}

/// The first web administrator, if this domain has no user account yet.
void bootstrapAdministrator(PlatformContainer c) @safe {
  auto result = c.authentication.ensureAdministrator(c.config.adminUser, c.config.adminPassword);
  if (!result.created)
    return;
  if (result.generatedPassword.length > 0)
    logWarn("Created web administrator '%s' of global account %s with the generated password '%s' — sign in at "
        ~ "/login and change it under Account (or set adminPassword / NEKO_ADMIN_PASSWORD before the first start)",
      result.userName, c.account.key, result.generatedPassword);
  else
    logInfo("Created web administrator '%s' of global account %s with the configured adminPassword",
      result.userName, c.account.key);
}

void logEndpoints(PlatformConfig config, FrontendController frontend) {
  logInfo("  REST   %s{overview,services,transfers}", config.restPath);
  logInfo("  OData  %s/$metadata", config.odataPath);
  logInfo("  Home   / (to /login or /start), /media/<subaccount>/<id> (public files)");
  logInfo("  Web    /login, /status, /monitoring, /security, /landscape (…/assignments, …/recovery, …/billing), "
      ~ "/files, /users, /roles, /accounts, /account");
  logInfo("  Calls  %scontext; X-Neko-Global-Account, X-Neko-Subaccount, X-Neko-Tenant, X-Neko-Space → X-Neko-Region",
    config.restPath);
  logInfo("  Guard  firewall %s, rate limit %s/min, IP rules in %s", config.firewallMode,
    config.rateLimitPerMinute, config.storage == "file" ? "iprules.json" : "memory");
  logInfo("  Ops    /health, /metrics (Prometheus), /api/v1/info%s", config.transport == "unix" ? ", /api/v1/socket" : "");
  if (frontend.available)
    logInfo("  Fiori  /index.html (%s)", frontend.location);
  else
    logInfo("  Fiori  not served (no frontend/index.html found; use the approuter or set frontendDir)");
}
