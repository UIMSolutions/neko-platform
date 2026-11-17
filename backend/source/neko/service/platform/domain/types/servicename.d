/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.domain.types.servicename;

import std.algorithm : all, canFind, startsWith;
import std.ascii : isAlphaNum;
import std.string : strip;
import neko.service.platform.domain.exceptions;

@safe:

/// Technical service name: 3–63 characters, lower-case letters, digits and '-'.
struct ServiceName {
  string value;

  this(string text) pure {
    auto name = text.strip;
    if (name.length < 3 || name.length > 63)
      throw new ValidationException("Service name must have 3 to 63 characters");
    if (!name.all!(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
      throw new ValidationException("Service name may only contain a-z, 0-9 and '-': " ~ name);
    if (name[0] == '-' || name[$ - 1] == '-')
      throw new ValidationException("Service name must not start or end with '-'");
    value = name;
  }
}
///
unittest {
    bool failed;
    try
        ServiceName("ab");
    catch (ValidationException)
        failed = true;
    assert(failed);

    failed = false;
    try
        ServiceName("a * 64");
    catch (ValidationException)
        failed = true;
    assert(failed);

    auto name = ServiceName("valid-name");
    assert(name.value == "valid-name");

    failed = false;
    try
        ServiceName("-invalid");
    catch (ValidationException)
        failed = true;
    assert(failed);

    failed = false;
    try
        ServiceName("invalid-");
    catch (ValidationException)
        failed = true;
    assert(failed);
    failed = false;
    try
        ServiceName("Invalid");
    catch (ValidationException)
        failed = true;
    assert(failed);
}
