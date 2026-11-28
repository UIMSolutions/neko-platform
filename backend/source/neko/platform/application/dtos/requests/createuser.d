/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.createuser;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct CreateUserRequest {
  string userName;
  string password;
  @optional string displayName;
  @optional string email;
  /// Role names; empty = ["viewer"].
  @optional string[] roles;
  @optional bool active = true;
}
