/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.globalaccount;

import neko.platform.domain;

@safe:

/// The global accounts of the instance. Kept in the instance's own store,
/// apart from the stores of the global accounts.
interface IGlobalAccountRepository {
  GlobalAccountEntry[] all();
  bool tryGet(string key, out GlobalAccountEntry entry);
  void save(GlobalAccountEntry entry);
  bool remove(string key);
}
