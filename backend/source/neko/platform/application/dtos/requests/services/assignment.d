/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.services.assignment;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

/// (Un)assign one service to several subaccounts.
struct ServiceAssignmentRequest {
  string service;
  string[] subaccounts;
  @optional bool assign = true;
}
