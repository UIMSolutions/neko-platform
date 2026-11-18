/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories;

import neko.platform.domain;

@safe:

interface IServiceRepository {
  PlatformService[] all();
  bool tryGet(ServiceId id, out PlatformService service);
  bool tryGetByName(string name, out PlatformService service);
  /// Insert or replace.
  void save(PlatformService service);
  bool remove(ServiceId id);
}

interface ITransferRepository {
  TransferPackage[] all();
  bool tryGet(TransferId id, out TransferPackage pkg);
  /// Transfers are an audit trail: they are inserted, never deleted.
  void save(TransferPackage pkg);
}
