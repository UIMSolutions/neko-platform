/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.services.passwords;

import neko.platform.domain.exceptions;

@safe:

/// Password rules: length only (NIST SP 800-63B: no composition rules).
struct PasswordPolicy {
  enum minLength = 10;
  enum maxLength = 1024;

  static void require(string password) pure {
    if (password.length < minLength)
      throw new ValidationException("Password must have at least 10 characters");
    if (password.length > maxLength)
      throw new ValidationException("Password is too long");
  }
}

///
unittest {
  PasswordPolicy.require("0123456789");
  bool failed;
  try
    PasswordPolicy.require("short");
  catch (ValidationException)
    failed = true;
  assert(failed);
}
