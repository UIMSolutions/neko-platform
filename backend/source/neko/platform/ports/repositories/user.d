/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.user;

import neko.platform.domain;

@safe:

interface IUserRepository {
  UserAccount[] all();
  bool tryGet(AccountId id, out UserAccount account);
  /// `name` in canonical (lower case) form.
  bool tryGetByName(string name, out UserAccount account);
  /// Insert or replace.
  void save(UserAccount account);
  bool remove(AccountId id);
}
