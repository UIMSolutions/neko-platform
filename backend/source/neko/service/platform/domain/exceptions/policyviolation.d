/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.domain.exceptions.policyviolation;

import neko.service.platform.domain.exceptions.platform;

@safe:

/// A security-domain rule forbids the operation (e.g. a downward data flow).
class PolicyViolationException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(403, msg, file, line);
  }
}