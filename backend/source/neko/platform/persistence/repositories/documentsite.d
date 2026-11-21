/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentsite;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

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
