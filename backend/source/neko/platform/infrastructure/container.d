/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Composition root: wires adapters to ports. The only place that knows all
/// concrete classes; everything else depends on interfaces.
///
/// One `PlatformContainer` per global account: global accounts are
/// physically separate, each container has its own stores in the global
/// account's data directory. `PlatformInstance` holds the registry of the
/// global accounts and builds their containers on first use.
module neko.platform.infrastructure.container;

import std.path : buildPath;
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
  /// The global account this container serves.
  GlobalAccountEntry account;
  /// Its data directory ("" with storage "memory").
  string dataDir;

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

/// The default global account of single-account setups (and tests).
GlobalAccountEntry defaultAccount(PlatformConfig config) {
  return GlobalAccountEntry("default", config.serviceName, null, "", true);
}

/// The data directory of a global account.
string accountDataDir(PlatformConfig config, SecurityDomain domain, const GlobalAccountEntry account) {
  auto root = config.effectiveDataDir(domain);
  return account.dataDir.length ? buildPath(root, account.dataDir) : root;
}

/// `store` overrides the configured storage (used by tests). `account`: the
/// global account (default: the default one, in the instance's data directory).
PlatformContainer buildContainer(PlatformConfig config, SecurityDomain domain, IDocumentStore store = null,
    GlobalAccountEntry account = GlobalAccountEntry.init) {
  auto c = new PlatformContainer;
  c.config = config;
  c.domain = domain;
  c.account = account.key.length ? account : defaultAccount(config);
  auto memory = store !is null || config.storage == "memory";
  c.dataDir = memory ? "" : accountDataDir(config, domain, c.account);

  if (store !is null)
    c.store = store;
  else if (memory)
    c.store = new MemoryDocumentStore;
  else
    c.store = new JsonFileDocumentStore(c.dataDir);
  if (memory)
    c.blobs = new MemoryBlobStore;
  else
    c.blobs = new FileSystemBlobStore(buildPath(c.dataDir, "files"));

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
  // The global account (its administrator: the first web user), the service
  // plans and a subaccount for this instance.
  landscape.ensureDefaults(c.account.isDefault ? config.serviceName : c.account.name, config.environment, defaultSite,
    config.adminUser.length ? [config.adminUser] : null);
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

/// The platform instance of one security domain: the registry of its global
/// accounts (in the instance's data directory) and their containers.
class PlatformInstance {
  PlatformConfig config;
  SecurityDomain domain;
  IDocumentStore store;
  IGlobalAccountRepository registry;
  IManageGlobalAccountsUseCase accounts;
  private PlatformContainer[string] containers;
  private bool memory;

  /// The container of a global account (built on first use; its data
  /// directory is created then).
  PlatformContainer container(string key) {
    if (auto c = key in containers)
      return *c;
    auto entry = accounts.get(key);
    auto c = buildContainer(config, domain, memory ? new MemoryDocumentStore : null, entry);
    containers[key] = c;
    return c;
  }

  /// The container of the default global account.
  PlatformContainer defaultContainer() {
    foreach (e; accounts.list())
      if (e.isDefault)
        return container(e.key);
    assert(0, "no default global account");
  }

  /// The containers built so far.
  PlatformContainer[] built() {
    return containers.values;
  }
}

/// `store` overrides the configured storage of the instance and all global
/// accounts (tests: everything in memory).
PlatformInstance buildInstance(PlatformConfig config, SecurityDomain domain, IDocumentStore store = null) {
  auto i = new PlatformInstance;
  i.config = config;
  i.domain = domain;
  i.memory = store !is null || config.storage == "memory";
  if (store !is null)
    i.store = store;
  else if (i.memory)
    i.store = new MemoryDocumentStore;
  else
    i.store = new JsonFileDocumentStore(config.effectiveDataDir(domain));
  i.registry = new DocumentGlobalAccountRepository(i.store);
  i.accounts = new ManageGlobalAccountsUseCase(i.registry, new LoggingEventPublisher, new SystemClock);
  auto def = i.accounts.ensureDefault(defaultAccount(config).key, config.serviceName);
  if (store !is null)
    i.containers[def.key] = buildContainer(config, domain, store, def); // the default one shares the test store
  return i;
}
