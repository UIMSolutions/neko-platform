/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports of the application services.
module neko.objects.ports.services.services;

import neko.objects;

mixin(ShowModule!());

@safe:

/// Reference data (value helps).
interface IObjectStoreCatalogService {
  Region[] regions();
  StorageClassInfo[] storageClasses();
}

/// Aggregated figures of a tenant.
interface IObjectStoreStatisticsService {
  ObjectStoreStatistics statistics(TenantId tenantId);
}
