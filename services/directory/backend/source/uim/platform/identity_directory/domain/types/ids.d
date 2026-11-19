/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Strongly typed identifiers of the Identity Directory aggregates.
/// (TenantId and UserId — the acting user — come from uim-framework.)
module neko.directory.domain.types.ids;

import neko.directory;

mixin(ShowModule!());

@safe:

struct DirectoryUserId { mixin(IdTemplate); }
struct GroupId { mixin(IdTemplate); }
struct SchemaId { mixin(IdTemplate); }
struct PasswordPolicyId { mixin(IdTemplate); }
struct ApiClientId { mixin(IdTemplate); }
struct AuditEventId { mixin(IdTemplate); }
