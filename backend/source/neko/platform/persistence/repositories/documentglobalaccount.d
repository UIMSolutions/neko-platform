/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentglobalaccount;

import std.algorithm : sort;
import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

class DocumentGlobalAccountRepository : IGlobalAccountRepository {
  mixin DocumentCollection!(GlobalAccountEntry, GlobalAccountEntryRecord, globalAccountsCollection);

  GlobalAccountEntry[] all() {
    auto list = loadAll();
    list.sort!((a, b) => a.isDefault != b.isDefault ? a.isDefault : a.key < b.key);
    return list;
  }

  bool tryGet(string key, out GlobalAccountEntry entry) {
    return find(key, entry);
  }

  void save(GlobalAccountEntry entry) {
    put(entry.key, entry);
  }

  bool remove(string key) {
    auto docs = store.load(globalAccountsCollection);
    if (key !in docs)
      return false;
    docs.remove(key);
    store.store(globalAccountsCollection, docs);
    return true;
  }
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentGlobalAccountRepository(new MemoryDocumentStore);
  repo.save(GlobalAccountEntry("zeta", "Zeta", ["zeta.example"], dataDirFor("zeta")));
  repo.save(GlobalAccountEntry("platform", "Platform", null, "", true));
  auto list = repo.all();
  assert(list.length == 2 && list[0].key == "platform" && list[1].hosts == ["zeta.example"]);
  GlobalAccountEntry z;
  assert(repo.tryGet("zeta", z) && z.dataDir == "global-accounts/zeta");
  assert(repo.remove("zeta") && !repo.remove("zeta"));
}
