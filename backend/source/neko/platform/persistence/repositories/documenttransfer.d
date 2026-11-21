/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documenttransfer;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

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
