/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.authentication.ports.repositories.policies;

import neko.service.authentication;

mixin(ShowModule!());

@safe:

/// Driven port: authorization policy persistence.
interface IPolicyRepository : ITenantRepository!(AuthorizationPolicy, PolicyId) {
  size_t countByApplication(TenantId tenantId, ApplicationId appId);
  /// Policies that apply to the application (explicitly assigned or global).
  AuthorizationPolicy[] findByApplication(TenantId tenantId, ApplicationId appId);
  void removeByApplication(TenantId tenantId, ApplicationId appId);
}
