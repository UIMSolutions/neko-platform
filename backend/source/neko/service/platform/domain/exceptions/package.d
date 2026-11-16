/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Business exceptions. Each carries an HTTP-like status code so driving
/// adapters can translate it without knowing the concrete type.
module neko.service.platform.domain.exceptions;

@safe:

class PlatformException : Exception {
  /// 400 validation, 403 policy, 404 not found, 409 conflict / state, 422 integrity
  int code;

  this(int code, string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, file, line);
    this.code = code;
  }
}

/// Input does not satisfy the business rules for a value or entity.
class ValidationException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(400, msg, file, line);
  }
}

/// A security-domain rule forbids the operation (e.g. a downward data flow).
class PolicyViolationException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(403, msg, file, line);
  }
}

class NotFoundException : PlatformException {
  this(string what, string id, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(404, what ~ " '" ~ id ~ "' not found", file, line);
  }
}

/// Uniqueness conflict, e.g. a service name that is already registered.
class ConflictException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(409, msg, file, line);
  }
}

/// A life-cycle transition that is not allowed from the current state.
class InvalidStateTransitionException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(409, msg, file, line);
  }
}

/// A transfer package was modified or corrupted in transit.
class IntegrityException : PlatformException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(422, msg, file, line);
  }
}
