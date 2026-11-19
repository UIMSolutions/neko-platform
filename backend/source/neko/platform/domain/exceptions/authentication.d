/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.exceptions.authentication;

import neko.platform.domain.exceptions.platform;

@safe:

/// Wrong credentials, or the account is locked / deactivated. The message
/// never says which, so it cannot be used to probe for user names.
class AuthenticationException : PlatformException {
  this(string msg = "Invalid user name or password", string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(401, msg, file, line);
  }
}
