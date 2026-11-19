/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// PBKDF2-HMAC-SHA256 credential adapter (RFC 8018) with random salts and
/// constant-time verification. Hash format:
///
///   pbkdf2-sha256$<iterations>$<salt base64url>$<hash base64url>
///
/// Hashes of the previous version ("<salt>$<SHA-256 hex>") still verify and
/// are reported by needsRehash, so they are upgraded at the next sign-in.
module neko.directory.infrastructure.security.credentials;

import std.base64 : Base64URLNoPadding;
import std.digest.hmac : HMAC;
import std.digest.sha : SHA256, sha256Of;
import std.digest : toHexString;
import std.random : uniform, Random, unpredictableSeed;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Derive a key with PBKDF2-HMAC-SHA256 (one 32-byte block).
ubyte[32] pbkdf2Sha256(const(ubyte)[] password, const(ubyte)[] salt, uint iterations) {
  auto mac = HMAC!SHA256(password);
  mac.start();
  mac.put(salt);
  mac.put(cast(const(ubyte)[])[0, 0, 0, 1]);
  ubyte[32] u = mac.finish();
  ubyte[32] result = u;
  foreach (_; 1 .. iterations) {
    mac.start();
    mac.put(u[]);
    u = mac.finish();
    foreach (i; 0 .. 32)
      result[i] ^= u[i];
  }
  return result;
}

/// Compare without early exit.
bool constantTimeEquals(const(ubyte)[] a, const(ubyte)[] b) pure nothrow @nogc {
  if (a.length != b.length)
    return false;
  ubyte diff;
  foreach (i; 0 .. a.length)
    diff |= a[i] ^ b[i];
  return diff == 0;
}

/// Random bytes from /dev/urandom (falls back to a seeded PRNG with a warning).
ubyte[] randomBytes(size_t count) @trusted {
  import std.stdio : File;

  auto buffer = new ubyte[count];
  try {
    auto f = File("/dev/urandom", "rb");
    scope (exit)
      f.close();
    if (f.rawRead(buffer).length == count)
      return buffer;
  } catch (Exception) {
  }
  logWarn("identity-directory: /dev/urandom unavailable — falling back to a pseudo random generator");
  auto rng = Random(unpredictableSeed);
  foreach (ref b; buffer)
    b = cast(ubyte) uniform(0, 256, rng);
  return buffer;
}

class Pbkdf2CredentialService : ICredentialService {
  protected uint iterations;

  this(uint iterations = 120_000) {
    this.iterations = iterations < 1000 ? 1000 : iterations;
  }

  string hashSecret(string plaintext) {
    auto salt = randomBytes(16);
    auto hash = pbkdf2Sha256(cast(const(ubyte)[]) plaintext, salt, iterations);
    return "pbkdf2-sha256$" ~ iterations.to!string ~ "$" ~ Base64URLNoPadding.encode(salt).idup
      ~ "$" ~ Base64URLNoPadding.encode(hash[]).idup;
  }

  bool verifySecret(string plaintext, string storedHash) {
    auto parts = storedHash.split("$");
    try {
      if (parts.length == 4 && parts[0] == "pbkdf2-sha256") {
        auto rounds = parts[1].to!uint;
        auto salt = Base64URLNoPadding.decode(parts[2]);
        auto expected = Base64URLNoPadding.decode(parts[3]);
        auto actual = pbkdf2Sha256(cast(const(ubyte)[]) plaintext, salt, rounds);
        return constantTimeEquals(actual[], expected);
      }
      if (parts.length == 2) { // legacy: <salt>$<hex(sha256(plaintext ~ salt))>
        auto actual = toHexString(sha256Of(plaintext ~ parts[0])).idup;
        return constantTimeEquals(cast(const(ubyte)[]) actual, cast(const(ubyte)[]) parts[1].toUpper);
      }
    } catch (Exception) {
    }
    return false;
  }

  bool needsRehash(string storedHash) {
    auto parts = storedHash.split("$");
    if (parts.length != 4 || parts[0] != "pbkdf2-sha256")
      return true;
    try
      return parts[1].to!uint < iterations;
    catch (Exception)
      return true;
  }

  string generateSecret(size_t bytes = 24) {
    return Base64URLNoPadding.encode(randomBytes(bytes)).idup;
  }
}

///
unittest {
  mixin(ShowTest!("Pbkdf2CredentialService"));

  // RFC 7914 section 11 test vector (PBKDF2-HMAC-SHA256, P="passwd", S="salt", c=1)
  auto v = pbkdf2Sha256(cast(const(ubyte)[]) "passwd", cast(const(ubyte)[]) "salt", 1);
  assert(toHexString!(LetterCase.lower)(v)[0 .. 16] == "55ac046e56e3089f");

  auto svc = new Pbkdf2CredentialService(1000);
  auto h = svc.hashSecret("Welcome2026");
  assert(h.startsWith("pbkdf2-sha256$1000$"));
  assert(svc.verifySecret("Welcome2026", h) && !svc.verifySecret("welcome2026", h));
  assert(h != svc.hashSecret("Welcome2026")); // random salt
  assert(!svc.needsRehash(h) && new Pbkdf2CredentialService(5000).needsRehash(h));

  // previous version: salt$HEX(sha256(password ~ salt))
  auto legacy = "abcd1234$" ~ toHexString(sha256Of("secret" ~ "abcd1234")).idup;
  assert(svc.verifySecret("secret", legacy) && svc.needsRehash(legacy));
  assert(!svc.verifySecret("x", "garbage"));
  assert(svc.generateSecret(32).length == 43);
}
