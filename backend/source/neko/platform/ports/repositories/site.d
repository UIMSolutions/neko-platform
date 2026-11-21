/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.site;

import neko.platform.domain;

@safe:


interface ISiteRepository {
  Site[] all();
  bool tryGet(string key, out Site site);
  /// Insert or replace.
  void save(Site site);
  bool remove(string key);
}
