/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.types.username;

import std.algorithm : all;
import std.string : strip, toLower;
import neko.platform.domain.exceptions;

@safe:

/// Login name: 2–64 characters a-z, 0-9, '.', '_', '-', '@'. Stored in lower
/// case, so "Jane" and "jane" are the same account.
struct UserName {
  string value;

  this(string text) pure {
    auto name = text.strip.toLower;
    if (name.length < 2 || name.length > 64)
      throw new ValidationException("User name must have 2 to 64 characters");
    if (!name.all!(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-' || c == '@'))
      throw new ValidationException("User name may only contain a-z, 0-9, '.', '_', '-' and '@'");
    value = name;
  }
}

///
unittest {
  assert(UserName("  Jane.Doe ").value == "jane.doe");
  foreach (bad; ["a", "jane doe", "jäne", ""]) {
    bool failed;
    try
      UserName(bad);
    catch (ValidationException)
      failed = true;
    assert(failed, bad);
  }
}
