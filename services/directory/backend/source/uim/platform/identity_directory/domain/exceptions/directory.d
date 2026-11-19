/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.exceptions.directory;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Base class of all business exceptions of the Identity Directory domain.
/// `status` is the HTTP-like status a driving adapter should report.
class DirectoryException : Exception {
  int status;

  this(string msg, int status = 400, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, file, line);
    this.status = status;
  }
}

/// Input violates a business rule (invalid user name, weak password, schema violation, ...).
class DirectoryValidationException : DirectoryException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, 422, file, line);
  }
}

/// A referenced aggregate does not exist.
class DirectoryNotFoundException : DirectoryException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, 404, file, line);
  }
}

/// The operation conflicts with the current state (duplicate name, in use, wrong status).
class DirectoryConflictException : DirectoryException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, 409, file, line);
  }
}

/// Credentials were rejected (wrong password, locked account, revoked client).
class DirectoryAuthenticationException : DirectoryException {
  this(string msg, string file = __FILE__, size_t line = __LINE__) pure nothrow {
    super(msg, 401, file, line);
  }
}

/// Throw a validation exception unless `condition` holds.
void validate(bool condition, lazy string message) {
  if (!condition)
    throw new DirectoryValidationException(message);
}

/// Throw a conflict exception unless `condition` holds.
void ensureState(bool condition, lazy string message) {
  if (!condition)
    throw new DirectoryConflictException(message);
}

/// Throw a not-found exception unless `condition` holds.
void ensureFound(bool condition, lazy string message) {
  if (!condition)
    throw new DirectoryNotFoundException(message);
}
