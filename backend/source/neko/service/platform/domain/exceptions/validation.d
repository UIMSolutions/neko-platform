/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.exceptions.validation;

import neko.platform.domain.exceptions.platform;

@safe:

/// Input does not satisfy the business rules for a value or entity.
class ValidationException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(400, msg, file, line);
  }
}
