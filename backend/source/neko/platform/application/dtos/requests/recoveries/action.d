/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.recoveries.action;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:
/// A failover or failback.
struct RecoveryActionRequest {
  /// Required: why (incident, maintenance, …).
  string reason;
  /// How long it took, if known.
  @optional long minutes;
}
