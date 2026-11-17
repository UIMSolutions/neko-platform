/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.authentication.ports.services.statistics;

import neko.service.authentication;

mixin(ShowModule!());

@safe:

/// Driving port: aggregated figures of a tenant.
interface IIdentityStatisticsService {
  IdentityStatistics statistics(TenantId tenantId);
}
