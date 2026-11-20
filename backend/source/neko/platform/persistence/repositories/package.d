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
