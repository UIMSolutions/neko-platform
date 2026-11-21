/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;

@safe:

/// Generic load/convert/store logic shared by the repositories.
private mixin template DocumentCollection(Entity, Record, string collection) {
  private IDocumentStore store;

  this(IDocumentStore store) {
    this.store = store;
  }

  private Entity[] loadAll() {
    Entity[] result;
    foreach (doc; store.load(collection))
      result ~= toEntity(deserializeJson!Record(doc));
    return result;
  }

  private bool find(string id, out Entity entity) {
    auto docs = store.load(collection);
    if (auto doc = id in docs) {
      entity = toEntity(deserializeJson!Record(*doc));
      return true;
    }
    return false;
  }

  private void put(string id, const Entity entity) {
    auto docs = store.load(collection);
    docs[id] = serializeToJson(toRecord(entity));
    store.store(collection, docs);
  }
}

class DocumentServiceRepository : IServiceRepository {
  mixin DocumentCollection!(PlatformService, ServiceRecord, servicesCollection);

  PlatformService[] all() {
    return loadAll();
  }

  bool tryGet(ServiceId id, out PlatformService service) {
    return find(id.value, service);
  }

  bool tryGetByName(string name, out PlatformService service) {
    foreach (s; loadAll())
      if (s.name.value == name) {
        service = s;
        return true;
      }
    return false;
  }

  void save(PlatformService service) {
    put(service.id.value, service);
  }

  bool remove(ServiceId id) {
    auto docs = store.load(servicesCollection);
    if (id.value !in docs)
      return false;
    docs.remove(id.value);
    store.store(servicesCollection, docs);
    return true;
  }
}

class DocumentTransferRepository : ITransferRepository {
  mixin DocumentCollection!(TransferPackage, TransferRecord, transfersCollection);

  TransferPackage[] all() {
    return loadAll();
  }

  bool tryGet(TransferId id, out TransferPackage pkg) {
    return find(id.value, pkg);
  }

  void save(TransferPackage pkg) {
    put(pkg.id.value, pkg);
  }
}

class DocumentUserRepository : IUserRepository {
  mixin DocumentCollection!(UserAccount, UserRecord, usersCollection);

  UserAccount[] all() {
    return loadAll();
  }

  bool tryGet(AccountId id, out UserAccount account) {
    return find(id.value, account);
  }

  bool tryGetByName(string name, out UserAccount account) {
    foreach (a; loadAll())
      if (a.userName.value == name) {
        account = a;
        return true;
      }
    return false;
  }

  void save(UserAccount account) {
    put(account.id.value, account);
  }

  bool remove(AccountId id) {
    auto docs = store.load(usersCollection);
    if (id.value !in docs)
      return false;
    docs.remove(id.value);
    store.store(usersCollection, docs);
    return true;
  }
}

class DocumentRoleRepository : IRoleRepository {
  mixin DocumentCollection!(Role, RoleRecord, rolesCollection);

  Role[] all() {
    return loadAll();
  }

  bool tryGet(string name, out Role role) {
    return find(name, role);
  }

  void save(Role role) {
    put(role.name.value, role);
  }

  bool remove(string name) {
    auto docs = store.load(rolesCollection);
    if (name !in docs)
      return false;
    docs.remove(name);
    store.store(rolesCollection, docs);
    return true;
  }
}

class DocumentSiteRepository : ISiteRepository {
  mixin DocumentCollection!(Site, SiteRecord, sitesCollection);

  Site[] all() {
    return loadAll();
  }

  bool tryGet(string key, out Site site) {
    return find(key, site);
  }

  void save(Site site) {
    put(site.key.value, site);
  }

  bool remove(string key) {
    auto docs = store.load(sitesCollection);
    if (key !in docs)
      return false;
    docs.remove(key);
    store.store(sitesCollection, docs);
    return true;
  }
}

class DocumentFileRepository : IFileRepository {
  mixin DocumentCollection!(StoredFile, FileRecord, filesCollection);

  StoredFile[] all() {
    return loadAll();
  }

  StoredFile[] ofSite(string site) {
    StoredFile[] result;
    foreach (f; loadAll())
      if (f.site.value == site)
        result ~= f;
    return result;
  }

  bool tryGet(FileId id, out StoredFile file) {
    return find(id.value, file);
  }

  void save(StoredFile file) {
    put(file.id.value, file);
  }

  bool remove(FileId id) {
    auto docs = store.load(filesCollection);
    if (id.value !in docs)
      return false;
    docs.remove(id.value);
    store.store(filesCollection, docs);
    return true;
  }
}

class DocumentIpRuleRepository : IIpRuleRepository {
  mixin DocumentCollection!(IpRule, IpRuleRecord, ipRulesCollection);

  IpRule[] all() {
    return loadAll();
  }

  bool tryGet(IpRuleId id, out IpRule rule) {
    return find(id.value, rule);
  }

  void save(IpRule rule) {
    put(rule.id.value, rule);
  }

  bool remove(IpRuleId id) {
    auto docs = store.load(ipRulesCollection);
    if (id.value !in docs)
      return false;
    docs.remove(id.value);
    store.store(ipRulesCollection, docs);
    return true;
  }
}

class DocumentLandscapeRepository : ILandscapeRepository {
  private IDocumentStore store;

  this(IDocumentStore store) {
    this.store = store;
  }

  Landscape load() {
    Landscape l;
    auto g = store.load(landscapeCollection);
    if (auto doc = "global" in g)
      l.global = toEntity(deserializeJson!GlobalAccountRecord(*doc));
    foreach (doc; store.load(directoriesCollection))
      l.directories ~= toEntity(deserializeJson!DirectoryRecord(doc));
    foreach (doc; store.load(subaccountsCollection))
      l.subaccounts ~= toEntity(deserializeJson!SubaccountRecord(doc));
    foreach (doc; store.load(plansCollection))
      l.plans ~= toEntity(deserializeJson!ServicePlanRecord(doc));
    import std.algorithm : sort;

    l.directories.sort!((a, b) => a.key < b.key);
    l.subaccounts.sort!((a, b) => a.key < b.key);
    l.plans.sort!((a, b) => a.key < b.key);
    return l;
  }

  void saveGlobal(GlobalAccount global) {
    auto docs = store.load(landscapeCollection);
    docs["global"] = serializeToJson(toRecord(global));
    store.store(landscapeCollection, docs);
  }

  void saveDirectory(Directory d) {
    put(directoriesCollection, d.key, serializeToJson(toRecord(d)));
  }

  bool removeDirectory(string key) {
    return drop(directoriesCollection, key);
  }

  void saveSubaccount(Subaccount s) {
    put(subaccountsCollection, s.key, serializeToJson(toRecord(s)));
  }

  bool removeSubaccount(string key) {
    return drop(subaccountsCollection, key);
  }

  void savePlan(ServicePlan p) {
    put(plansCollection, p.key, serializeToJson(toRecord(p)));
  }

  bool removePlan(string key) {
    return drop(plansCollection, key);
  }

  private void put(string collection, string key, Json doc) {
    auto docs = store.load(collection);
    docs[key] = doc;
    store.store(collection, docs);
  }

  private bool drop(string collection, string key) {
    auto docs = store.load(collection);
    if (key !in docs)
      return false;
    docs.remove(key);
    store.store(collection, docs);
    return true;
  }
}

class DocumentUsageRepository : IUsageRepository {
  private IDocumentStore store;

  this(IDocumentStore store) {
    this.store = store;
  }

  UsageRecord[] ofMonth(string month) {
    UsageRecord[] result;
    foreach (doc; store.load(usageCollection)) {
      auto u = toEntity(deserializeJson!UsageDocument(doc));
      if (u.month == month)
        result ~= u;
    }
    return result;
  }

  string[] months() {
    import std.algorithm : sort, uniq;
    import std.array : array;

    string[] list;
    foreach (doc; store.load(usageCollection))
      list ~= doc["month"].get!string;
    list.sort!((a, b) => a > b);
    return list.uniq.array;
  }

  void add(const(UsageRecord)[] deltas) {
    if (deltas.length == 0)
      return;
    auto docs = store.load(usageCollection);
    foreach (d; deltas) {
      auto key = d.month ~ "|" ~ d.site;
      UsageRecord current = UsageRecord(d.month, d.site);
      if (auto doc = key in docs)
        current = toEntity(deserializeJson!UsageDocument(*doc));
      current.merge(d);
      docs[key] = serializeToJson(toRecord(current));
    }
    store.store(usageCollection, docs);
  }
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto store = new MemoryDocumentStore;
  auto repo = new DocumentLandscapeRepository(store);
  auto g = GlobalAccount();
  g.name = "ACME";
  g.entitlements = [Entitlement("sites.site", 4)];
  repo.saveGlobal(g);
  Subaccount s;
  s.key = "shop-prod";
  s.name = "Shop";
  s.subdomain = "acme-shop-prod";
  s.stage = Stage.prod;
  s.domain = SecurityDomain.confidential;
  s.roleCollections = [RoleCollection("Admins", "", ["sites.manage"], ["jane"])];
  repo.saveSubaccount(s);
  foreach (p; defaultPlans())
    repo.savePlan(p);
  auto l = repo.load();
  assert(l.global.name == "ACME" && l.global.entitlements[0].quota == 4 && l.plans.length == defaultPlans().length);
  assert(l.subaccounts[0].stage == Stage.prod && l.subaccounts[0].domain == SecurityDomain.confidential);
  assert(l.subaccounts[0].roleCollections[0].members == ["jane"]);
  assert(repo.removeSubaccount("shop-prod") && repo.load().subaccounts.length == 0);

  auto usage = new DocumentUsageRepository(store);
  usage.add([UsageRecord("2026-11", "shop", 10, 100, 7)]);
  usage.add([UsageRecord("2026-11", "shop", 5, 50, 3), UsageRecord("2026-10", "shop", 1, 1, 1)]);
  auto nov = usage.ofMonth("2026-11");
  assert(nov.length == 1 && nov[0].requests == 15 && nov[0].bytesOut == 150 && nov[0].peakStorageBytes == 7);
  assert(usage.months == ["2026-11", "2026-10"]);
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto rules = new DocumentIpRuleRepository(new MemoryDocumentStore);
  IpRule r;
  r.id = IpRuleId("1");
  r.network = IpNetwork("2001:DB8::/32");
  r.action = IpAction.allow;
  r.scope_ = NetworkScope.api;
  rules.save(r);
  IpRule back;
  assert(rules.tryGet(IpRuleId("1"), back) && back.network.toString == "2001:db8::/32");
  assert(back.action == IpAction.allow && back.scope_ == NetworkScope.api && rules.remove(IpRuleId("1")));
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentServiceRepository(new MemoryDocumentStore);
  PlatformService s;
  s.id = ServiceId("1");
  s.name = ServiceName("alpha");
  repo.save(s);

  PlatformService found;
  assert(repo.tryGetByName("alpha", found) && found.id.value == "1");
  assert(repo.all.length == 1);
  assert(repo.remove(ServiceId("1")) && !repo.remove(ServiceId("1")));
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentUserRepository(new MemoryDocumentStore);
  UserAccount a;
  a.id = AccountId("1");
  a.userName = UserName("jane");
  a.roles = [adminRole];
  a.passwordHash = "h";
  repo.save(a);

  UserAccount found;
  assert(repo.tryGetByName("jane", found) && found.isAdmin && found.passwordHash == "h");
  assert(repo.remove(AccountId("1")) && repo.all.length == 0);
}
