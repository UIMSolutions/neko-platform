/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentuser;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

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
