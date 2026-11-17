/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.management.ports.repositories.subscriptions;
// import neko.service.management.domain.entities.subscription;

import neko.service.management;

mixin(ShowModule!());

@safe:
/// Port: outgoing — subscription persistence.
interface ISubscriptionRepository : ITenantRepository!(Subscription, SubscriptionId) {

  Subscription[] findBySubaccount(TenantId tenantId, SubaccountId subaccountId);
  Subscription[] findByApp(TenantId tenantId, SubaccountId subaccountId, string appName);
  Subscription[] findByStatus(TenantId tenantId, SubaccountId subaccountId, SubscriptionStatus status);
  
}
