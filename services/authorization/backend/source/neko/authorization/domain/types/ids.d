/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Typed identifiers (no accidental mix-up of policy and application ids).
module neko.authorization.domain.types.ids;

import neko.authorization;

mixin(ShowModule!());

@safe:

struct ManagedApplicationId {
  mixin(IdTemplate);
}

struct ApplicationApiId {
  mixin(IdTemplate);
}

struct PolicyId {
  mixin(IdTemplate);
}

struct PolicyAssignmentId {
  mixin(IdTemplate);
}

struct DecisionRecordId {
  mixin(IdTemplate);
}

/// A new random resource id.
string newResourceId() @trusted {
  return randomUUID().toString;
}
