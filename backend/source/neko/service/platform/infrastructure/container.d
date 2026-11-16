/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Composition root: wires adapters to ports. The only place that knows all
/// concrete classes; everything else depends on interfaces.
module neko.service.platform.infrastructure.container;

import neko.service.platform.domain;
import neko.service.platform.application;
import neko.service.platform.ports;
import neko.service.platform.persistence;
import neko.service.platform.infrastructure.clients;
import neko.service.platform.infrastructure.configuration;
import neko.service.platform.infrastructure.logging;

@safe:

class PlatformContainer {
  PlatformConfig config;
  SecurityDomain domain;

  IDocumentStore store;
  IServiceRepository serviceRepository;
  ITransferRepository transferRepository;
  LoggingEventPublisher events;
  IClock clock;

  IManageServicesUseCase services;
  ICheckServiceHealthUseCase health;
  ITransferPackagesUseCase transfers;
  IPlatformOverviewUseCase overview;
}

/// `store` overrides the configured storage (used by tests).
PlatformContainer buildContainer(PlatformConfig config, SecurityDomain domain, IDocumentStore store = null) {
  auto c = new PlatformContainer;
  c.config = config;
  c.domain = domain;

  if (store !is null)
    c.store = store;
  else if (config.storage == "memory")
    c.store = new MemoryDocumentStore;
  else
    c.store = new JsonFileDocumentStore(config.effectiveDataDir(domain));

  c.serviceRepository = new DocumentServiceRepository(c.store);
  c.transferRepository = new DocumentTransferRepository(c.store);
  c.events = new LoggingEventPublisher;
  c.clock = new SystemClock;
  auto ids = new UuidGenerator;

  c.services = new ManageServicesUseCase(c.serviceRepository, c.events, c.clock, ids, domain);
  c.health = new CheckServiceHealthUseCase(c.serviceRepository,
    new HttpHealthGateway(config.healthTimeoutSeconds), c.events, c.clock);
  c.transfers = new TransferPackagesUseCase(c.transferRepository, c.events, c.clock, ids, domain,
    cast(size_t) config.maxPayloadBytes);
  c.overview = new PlatformOverviewUseCase(c.serviceRepository, c.transferRepository, domain, config.environment);
  return c;
}
