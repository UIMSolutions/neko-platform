/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.exceptions.invalidstatetransition;

import neko.platform.domain.exceptions.platform;

@safe:

/// A life-cycle transition that is not allowed from the current state.
class InvalidStateTransitionException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(409, msg, file, line);
  }
}