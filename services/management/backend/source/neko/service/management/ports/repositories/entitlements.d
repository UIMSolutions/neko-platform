/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.management.ports.repositories.entitlements;
// import neko.service.management.domain.entities.entitlement;

import neko.service.management;

mixin(ShowModule!());

@safe:
/// Port: outgoing — entitlement persistence.
interface IEntitlementRepository : ITenantRepository!(Entitlement, EntitlementId) {

  Entitlement[] findByGlobalAccount(TenantId tenantId, GlobalAccountId globalAccountId);
  Entitlement[] findBySubaccount(TenantId tenantId, SubaccountId subaccountId);
  Entitlement[] findByDirectory(TenantId tenantId, DirectoryId directoryId);
  Entitlement[] findByServicePlan(TenantId tenantId, GlobalAccountId globalAccountId, ServicePlanId planId);
  
}
