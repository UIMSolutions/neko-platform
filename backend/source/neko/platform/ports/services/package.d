/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports for application-wide services (time, identifiers). Use cases depend
/// on these abstractions so tests can supply deterministic implementations.
module neko.platform.ports.services;

import std.datetime.systime : SysTime;

@safe:

interface IClock {
  SysTime now();
}

interface IIdGenerator {
  string newId();
}

/// Password hashing and secure random values (driven port; OpenSSL adapter in
/// infrastructure.security.passwords).
interface IPasswordHasher {
  /// A salted, slow hash that embeds its parameters.
  string hash(string password);
  /// Constant-time check; false for malformed hashes.
  bool verify(string password, string hash);
  /// 32 random bytes, base64url encoded (session tokens, generated passwords).
  string randomSecret();
}
