/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.ports.services.seed;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Installs the predefined content (password policies, enterprise user schema)
/// into a tenant. Idempotent: existing names are kept.
interface IDirectorySeedService {
  SeedReport seed(TenantId tenantId, UserId actor);
}
