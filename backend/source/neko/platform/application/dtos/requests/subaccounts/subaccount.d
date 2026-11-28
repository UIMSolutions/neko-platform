/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.subaccounts.subaccount;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct SubaccountRequest {
  string key;
  string name;
  @optional string description;
  @optional string directory;
  @optional string region = "eu10";
  /// "" = from the subdomain scheme of the global account
  @optional string subdomain;
  @optional string purpose;
  @optional string stage = "dev";
  /// Security domain label; "" = this instance's domain
  @optional string domain;
  @optional string costCenter;
  @optional bool betaFeatures;
}
