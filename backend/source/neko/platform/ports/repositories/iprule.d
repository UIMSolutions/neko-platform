/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.iprule;

import neko.platform.domain;

@safe:

interface IIpRuleRepository {
  IpRule[] all();
  bool tryGet(IpRuleId id, out IpRule rule);
  /// Insert or replace.
  void save(IpRule rule);
  bool remove(IpRuleId id);
}

