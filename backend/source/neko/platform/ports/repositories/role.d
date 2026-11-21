/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.role;

import neko.platform.domain;

@safe:

interface IRoleRepository {
  Role[] all();
  /// `name` in canonical (lower case) form.
  bool tryGet(string name, out Role role);
  /// Insert or replace.
  void save(Role role);
  bool remove(string name);
}

