/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Entry point. One executable per security domain (dub --config=open|restricted|confidential|secret);
/// the domain is fixed at compile time so a binary can never run in the wrong domain.
module app;

import std.array : join;
import vibe.core.core : runApplication;
import vibe.core.log;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerSettings, listenHTTP;
import vibe.web.rest : registerRestInterface;
import neko.service.platform;

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

  // Order matters: middleware first, the static catch-all last.
  new SecurityMiddleware(config).registerRoutes(router);
  new HealthController(config, selfDomain).registerRoutes(router);
  router.registerRestInterface(new PlatformApi(c.services, c.health, c.transfers, c.overview), config.restPath);
  new PlatformODataController(c.services, c.health, c.transfers, c.overview, config.odataPath).registerRoutes(router);
  new StatusPageController(c.overview, c.services, c.events, config.serviceName).registerRoutes(router);
  auto frontend = new FrontendController(config.frontendDir);
  frontend.registerRoutes(router);

  auto worker = new HealthCheckWorker(c.health, config.healthCheckIntervalSeconds);
  worker.start();

  logInfo("%s — domain %s (export=%s, import=%s), storage %s, config from %s", config.serviceName,
    selfDomain.label, selfDomain.canExport, selfDomain.canImport, c.store.describe, config.sources.join(" → "));

  if (config.transport == "unix") {
    auto listener = listenOnUnixSocket(config.effectiveSocketPath(selfDomain), router);
    scope (exit)
      listener.stopListening();
    logEndpoints(config, frontend);
    return runApplication();
  }

  auto settings = new HTTPServerSettings;
  settings.port = config.effectivePort(selfDomain);
  settings.bindAddresses = [config.host];
  auto listener = listenHTTP(settings, router);
  scope (exit)
    listener.stopListening();
  logEndpoints(config, frontend);
  return runApplication();
}

void logEndpoints(PlatformConfig config, FrontendController frontend) {
  logInfo("  REST   %s{overview,services,transfers}", config.restPath);
  logInfo("  OData  %s/$metadata", config.odataPath);
  logInfo("  Web    /status, /health, /api/v1/info");
  if (frontend.available)
    logInfo("  Fiori  /index.html (%s)", frontend.location);
  else
    logInfo("  Fiori  not served (no frontend/index.html found; use the approuter or set frontendDir)");
}
