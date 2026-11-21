/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentiprule;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

class DocumentIpRuleRepository : IIpRuleRepository {
  mixin DocumentCollection!(IpRule, IpRuleRecord, ipRulesCollection);

  IpRule[] all() {
    return loadAll();
  }

  bool tryGet(IpRuleId id, out IpRule rule) {
    return find(id.value, rule);
  }

  void save(IpRule rule) {
    put(rule.id.value, rule);
  }

  bool remove(IpRuleId id) {
    auto docs = store.load(ipRulesCollection);
    if (id.value !in docs)
      return false;
    docs.remove(id.value);
    store.store(ipRulesCollection, docs);
    return true;
  }
}
///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentIpRuleRepository(new MemoryDocumentStore);
  IpRule r;
  r.id = IpRuleId("1");
  r.network = IpNetwork("2001:DB8::/32");
  r.action = IpAction.allow;
  r.scope_ = NetworkScope.api;
  repo.save(r);

  IpRule found;
  assert(repo.tryGet(IpRuleId("1"), found) && found.network.toString == "2001:db8::/32");
  assert(found.action == IpAction.allow && found.scope_ == NetworkScope.api && repo.remove(IpRuleId("1")));
}
