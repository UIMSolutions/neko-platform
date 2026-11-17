/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.domain.exceptions.notfound;

import neko.service.platform.domain.exceptions.platform;

@safe:

class NotFoundException : PlatformException {
  this(string what, string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(404, what ~ " '" ~ id ~ "' not found", file, line);
  }
}