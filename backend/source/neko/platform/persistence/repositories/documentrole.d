/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentrole;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

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
