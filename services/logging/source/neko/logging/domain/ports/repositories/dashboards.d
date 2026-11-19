/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.domain.ports.repositories.dashboards;
// import neko.logging.domain.entities.dashboard;

import neko.logging;

mixin(ShowModule!());

@safe:
interface IDashboardRepository : ITenantRepository!(Dashboard, DashboardId) {

  bool existsDefault(TenantId tenantId);
  Dashboard findDefault(TenantId tenantId);
  void removeDefault(TenantId tenantId);

}
