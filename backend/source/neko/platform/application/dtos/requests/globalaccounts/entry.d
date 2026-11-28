/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.globalaccounts.entry;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

/// A global account of the instance (registry entry).
struct GlobalAccountEntryRequest {
  string key;
  @optional string name;
  /// Host names that select the global account.
  @optional string[] hosts;
  @optional string description;
}

