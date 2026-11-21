/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Composition root: wires adapters to ports. The only place that knows all
/// concrete classes; everything else depends on interfaces.
module neko.platform.infrastructure.container;

import neko.platform.domain;
import neko.platform.application;
import neko.platform.ports;
import neko.platform.persistence;
import neko.platform.infrastructure.clients;
import neko.platform.infrastructure.configuration;
import neko.platform.infrastructure.logging;
import neko.platform.infrastructure.security : OpensslPasswordHasher;

@safe:

class PlatformContainer {
  PlatformConfig config;
  SecurityDomain domain;

  IDocumentStore store;
  IServiceRepository serviceRepository;
  ITransferRepository transferRepository;
  IUserRepository userRepository;
  IRoleRepository roleRepository;
  ISiteRepository siteRepository;
  IFileRepository fileRepository;
  IBlobStore blobs;
  IIpRuleRepository ipRuleRepository;
  ILandscapeRepository landscapeRepository;
  IUsageRepository usageRepository;
  IPasswordHasher passwords;
  LoggingEventPublisher events;
  IClock clock;

  IManageServicesUseCase services;
  ICheckServiceHealthUseCase health;
  ITransferPackagesUseCase transfers;
  IPlatformOverviewUseCase overview;
  IManageUsersUseCase users;
  IAuthenticateUseCase authentication;
  IManageRolesUseCase roles;
  IManageSitesUseCase sites;
  IManageFilesUseCase files;
  IManageNetworkUseCase network;
  IManageLandscapeUseCase landscape;
  IBillingUseCase billing;
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
  if (store !is null || config.storage == "memory")
    c.blobs = new MemoryBlobStore;
  else
    c.blobs = new FileSystemBlobStore(config.effectiveFilesDir(domain));

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
  c.userRepository = new DocumentUserRepository(c.store);
  c.roleRepository = new DocumentRoleRepository(c.store);
  c.passwords = new OpensslPasswordHasher;
  c.roles = new ManageRolesUseCase(c.roleRepository, c.userRepository, c.events, c.clock);
  // Before any account is touched (also by the CLI): user roles must exist.
  c.roles.ensureBuiltIns();
  c.siteRepository = new DocumentSiteRepository(c.store);
  c.fileRepository = new DocumentFileRepository(c.store);
  c.sites = new ManageSitesUseCase(c.siteRepository, c.fileRepository, c.userRepository, c.events, c.clock);
  // Before anything is served: "/" shows the default site.
  auto defaultSite = c.sites.ensureDefaultSite(config.serviceName, config.defaultLanguage);
  c.files = new ManageFilesUseCase(c.fileRepository, c.siteRepository, c.blobs, c.userRepository, c.events, c.clock,
    ids, FileLimits(config.maxUploadBytes, config.siteQuotaBytes));
  c.landscapeRepository = new DocumentLandscapeRepository(c.store);
  c.usageRepository = new DocumentUsageRepository(c.store);
  auto landscape = new ManageLandscapeUseCase(c.landscapeRepository, c.usageRepository, c.siteRepository, c.events,
    c.clock, domain);
  // The global account, the service plans and a subaccount for this instance.
  landscape.ensureDefaults(config.serviceName, config.environment, defaultSite);
  c.landscape = landscape;
  c.billing = landscape;
  c.ipRuleRepository = new DocumentIpRuleRepository(c.store);
  c.network = new ManageNetworkUseCase(c.ipRuleRepository, c.events, c.clock, ids);
  auto users = new ManageUsersUseCase(c.userRepository, c.roleRepository, c.passwords, c.events, c.clock, ids,
    c.siteRepository);
  c.users = users;
  c.authentication = users;
  c.overview = new PlatformOverviewUseCase(c.serviceRepository, c.transferRepository, domain, config.environment);
  return c;
}
