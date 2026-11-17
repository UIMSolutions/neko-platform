/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.authentication.ports.repositories.applications;

import neko.service.authentication;

mixin(ShowModule!());

@safe:

/// Driven port: application / service provider persistence.
interface IApplicationRepository : ITenantRepository!(Application, ApplicationId) {
  bool existsByClient(TenantId tenantId, string clientId);
  Application findByClient(TenantId tenantId, string clientId);
  void removeByClient(TenantId tenantId, string clientId);
}
