/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.iprules.add;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct AddIpRuleRequest {
  /// Address or CIDR network ("10.0.0.0/8", "2001:db8::/32").
  string network;
  /// "allow" | "deny"
  string action;
  /// "all" | "admin" | "api"
  @optional string scope_ = "admin";
  @optional string note;
}
