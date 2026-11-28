/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.registerservice;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct RegisterServiceRequest {
  string name;
  @optional string description;
  /// "open" | "restricted" | "confidential" | "secret"; empty = platform domain
  @optional string classification;
  @optional string baseUrl;
  @optional string healthPath;
  /// Activate right after registration.
  @optional bool activate;
}
