/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

public: 
  import neko.platform.persistence.repositories.documentfile;
  import neko.platform.persistence.repositories.documentglobalaccount;
  import neko.platform.persistence.repositories.documentiprule;
  import neko.platform.persistence.repositories.documentlandscape;
  import neko.platform.persistence.repositories.documentrole;
  import neko.platform.persistence.repositories.documentservice;
  import neko.platform.persistence.repositories.documenttransfer;
  import neko.platform.persistence.repositories.documentusage;
  import neko.platform.persistence.repositories.documentuser;

@safe:

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto store = new MemoryDocumentStore;
  auto repo = new DocumentLandscapeRepository(store);
  auto g = GlobalAccount();
  g.name = "ACME";
  g.entitlements = [Entitlement("files.storage", 4)];
  repo.saveGlobal(g);
  Subaccount s;
  s.key = "shop-prod";
  s.name = "Shop";
  s.subdomain = "acme-shop-prod";
  s.stage = Stage.prod;
  s.domain = SecurityDomain.confidential;
  s.roleCollections = [RoleCollection("Admins", "", ["files.manage"], ["jane"])];
  repo.saveSubaccount(s);
  foreach (p; defaultPlans())
    repo.savePlan(p);
  auto l = repo.load();
  assert(l.global.name == "ACME" && l.global.entitlements[0].quota == 4 && l.plans.length == defaultPlans().length);
  assert(l.subaccounts[0].stage == Stage.prod && l.subaccounts[0].domain == SecurityDomain.confidential);
  assert(l.subaccounts[0].roleCollections[0].members == ["jane"]);
  assert(repo.removeSubaccount("shop-prod") && repo.load().subaccounts.length == 0);

  auto usage = new DocumentUsageRepository(store);
  usage.add([UsageRecord("2026-11", "shop-prod", 10, 100, 7)]);
  usage.add([UsageRecord("2026-11", "shop-prod", 5, 50, 3), UsageRecord("2026-10", "shop-prod", 1, 1, 1)]);
  auto nov = usage.ofMonth("2026-11");
  assert(nov.length == 1 && nov[0].requests == 15 && nov[0].bytesOut == 150 && nov[0].peakStorageBytes == 7);
  assert(usage.months == ["2026-11", "2026-10"]);
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto rules = new DocumentIpRuleRepository(new MemoryDocumentStore);
  IpRule r;
  r.id = IpRuleId("1");
  r.network = IpNetwork("2001:DB8::/32");
  r.action = IpAction.allow;
  r.scope_ = NetworkScope.api;
  rules.save(r);
  IpRule back;
  assert(rules.tryGet(IpRuleId("1"), back) && back.network.toString == "2001:db8::/32");
  assert(back.action == IpAction.allow && back.scope_ == NetworkScope.api && rules.remove(IpRuleId("1")));
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentServiceRepository(new MemoryDocumentStore);
  PlatformService s;
  s.id = ServiceId("1");
  s.name = ServiceName("alpha");
  repo.save(s);

  PlatformService found;
  assert(repo.tryGetByName("alpha", found) && found.id.value == "1");
  assert(repo.all.length == 1);
  assert(repo.remove(ServiceId("1")) && !repo.remove(ServiceId("1")));
}

///
unittest {
  import neko.platform.persistence.storages : MemoryDocumentStore;

  auto repo = new DocumentUserRepository(new MemoryDocumentStore);
  UserAccount a;
  a.id = AccountId("1");
  a.userName = UserName("jane");
  a.roles = [adminRole];
  a.passwordHash = "h";
  repo.save(a);

  UserAccount found;
  assert(repo.tryGetByName("jane", found) && found.isAdmin && found.passwordHash == "h");
  assert(repo.remove(AccountId("1")) && repo.all.length == 0);
}
