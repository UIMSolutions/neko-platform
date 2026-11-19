/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.ports.gateways.credentials;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Driven port: one-way hashing of passwords and client secrets, and
/// generation of random secrets (PBKDF2 / HSM / KMS behind it).
interface ICredentialService {
  /// Salted, slow one-way hash.
  string hashSecret(string plaintext);
  /// Constant-time verification against a stored hash.
  bool verifySecret(string plaintext, string storedHash);
  /// True if a stored hash uses an outdated algorithm or work factor.
  bool needsRehash(string storedHash);
  /// URL-safe random secret with `bytes` bytes of entropy.
  string generateSecret(size_t bytes = 24);
}
