/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentlandscape;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

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
///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentLandscapeRepository(new MemoryDocumentStore);
  GlobalAccount g;
  g.name = "ACME";
  repo.saveGlobal(g);

  Landscape l = repo.load();
  assert(l.global.name == "ACME");

  // subaccounts stored by earlier versions (before tenants, with sites): they
  // get the default tenant and space; the site fields are ignored
  auto store = new MemoryDocumentStore;
  store.store("subaccounts", ["old": parseJsonString(`{"key": "old", "name": "Old", "region": "eu10",
    "subdomain": "old", "stage": "dev", "domain": "open", "sites": ["main"], "createdAt": "", "modifiedAt": "",
    "tenants": [{"key": "t1", "isDefault": true, "spaces": [{"key": "default", "sites": ["shop"]}]}]}`)]);
  auto old = new DocumentLandscapeRepository(store).load().subaccounts[0];
  assert(old.tenants.length == 1 && old.tenants[0].isDefault && old.tenants[0].spaces[0].isDefault);
  assert(!old.recovery.enabled);
  old.tenants ~= Tenant("eu", "EU", "", false, [Space("default"), Space("qa", "QA")]);
  old.admins = ["ann"];
  old.services = ["files"];
  old.recovery.enabled = true;
  old.recovery.secondaryRegion = "eu20";
  auto repo2 = new DocumentLandscapeRepository(store);
  repo2.saveSubaccount(old);
  auto back = repo2.load().subaccounts[0];
  assert(back.tenants.length == 2 && back.tenants[1].spaces[1].key == "qa" && back.admins == ["ann"]);
  assert(back.services == ["files"] && back.recovery.enabled && back.recovery.secondaryRegion == "eu20");
  Directory d;
  d.key = "dir1";
  repo.saveDirectory(d);

  l = repo.load();
  assert(l.directories.length == 1 && l.directories[0].key == "dir1");
  assert(repo.removeDirectory("dir1") && repo.load().directories.length == 0);
}
  