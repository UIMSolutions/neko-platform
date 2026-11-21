/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentfile;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

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
///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentFileRepository(new MemoryDocumentStore);
  StoredFile f;
  f.id = FileId("1");
  f.site = SiteId("shop");
  repo.save(f);

  StoredFile found;
  assert(repo.tryGet(FileId("1"), found) && found.site.value == "shop");
  assert(repo.ofSite("shop").length == 1);
  assert(repo.remove(FileId("1")) && !repo.remove(FileId("1")));
}

