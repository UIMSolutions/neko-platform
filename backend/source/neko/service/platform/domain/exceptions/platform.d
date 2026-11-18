/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.exceptions.platform;

@safe:

/// Base class for all platform-related exceptions.
class PlatformException : Exception {
  /// 400 validation, 403 policy, 404 not found, 409 conflict / state, 422 integrity
  int code;

  this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, file, line);
    this.code = code;
  }
}