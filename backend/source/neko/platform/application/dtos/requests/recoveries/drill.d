/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.recoveries.drill;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

/// A failover rehearsal.
struct RecoveryDrillRequest {
  /// How long the failover took in the drill.
  long minutes;
  /// Whether the service worked in the secondary region.
  @optional bool worked = true;
  @optional string notes;
}
