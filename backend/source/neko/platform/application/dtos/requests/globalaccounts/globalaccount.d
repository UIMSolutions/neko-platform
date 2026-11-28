/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.globalaccounts.globalaccount;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct GlobalAccountRequest {
  string name;
  @optional string subdomainPrefix;
  @optional string subdomainPattern;
  /// "CPEA" | "PAYG" | "subscription"
  @optional string contract;
  @optional string currency;
  @optional string costCenter;
  @optional string[] admins;
}
