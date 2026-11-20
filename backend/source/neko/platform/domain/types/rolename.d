/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.types.rolename;

import std.algorithm : all;
import std.ascii : isDigit, isLower;
import std.string : strip, toLower;
import neko.platform.domain.exceptions;

@safe:

/// Key of a role: 2–32 characters a-z, 0-9, '.', '_', '-', starting with a
/// letter. Stored in lower case; it identifies the role and cannot change.
struct RoleName {
  string value;

  this(string text) pure {
    auto name = text.strip.toLower;
    if (name.length < 2 || name.length > 32)
      throw new ValidationException("Role name must have 2 to 32 characters");
    if (!name[0].isLower || !name.all!(c => c.isLower || c.isDigit || c == '.' || c == '_' || c == '-'))
      throw new ValidationException("Role name must start with a-z and may only contain a-z, 0-9, '.', '_' and '-'");
    value = name;
  }
}

///
unittest {
  assert(RoleName(" Ops-Team ").value == "ops-team");
  foreach (bad; ["a", "1ops", "ops team", "öps", "", "x".replicate(33)]) {
    bool failed;
    try
      RoleName(bad);
    catch (ValidationException)
      failed = true;
    assert(failed, bad);
  }
}

version (unittest) import std.array : replicate;
