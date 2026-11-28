/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.services.plan;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct ServicePlanRequest {
  string key;
  string service;
  string plan;
  @optional string description;
  string unit;
  double unitSize = 1;
  double price = 0;
  /// "none" | "requests" | "egressBytes" | "storageBytes"
  @optional string meter = "none";
}
