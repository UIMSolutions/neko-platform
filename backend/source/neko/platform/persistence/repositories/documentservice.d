/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentservice;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:


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
