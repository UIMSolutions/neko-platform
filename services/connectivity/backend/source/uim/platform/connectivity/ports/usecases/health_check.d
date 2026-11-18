/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.connectivity.ports.usecases.health_check;

import neko.connectivity;

mixin(ShowModule!());

@safe:

/// One monitoring pass over a tenant: missed heartbeats, certificate expiry,
/// destination reachability and log retention.
interface IHealthCheckUseCase {
  HealthCheckReport run(TenantId tenantId);
}
