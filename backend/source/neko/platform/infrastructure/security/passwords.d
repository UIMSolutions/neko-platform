/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Password hashing adapter: PBKDF2-HMAC-SHA256 and random bytes from OpenSSL
/// (libcrypto is linked through vibe.d already).
///
/// Format: pbkdf2-sha256$<rounds>$<salt base64>$<hash base64>. The rounds are
/// part of the hash, so they can be raised later without breaking old hashes.
module neko.platform.infrastructure.security.passwords;

import std.algorithm : min;
import std.array : split;
import std.base64 : Base64, Base64URLNoPadding;
import std.conv : to;
import std.exception : enforce;
import std.format : format;
import std.string : toStringz;
import vibe.core.concurrency : async;
import vibe.core.task : Task;
import neko.platform.ports.services : IPasswordHasher;

@safe:

private extern (C) nothrow @nogc {
  const(void)* EVP_sha256();
  int PKCS5_PBKDF2_HMAC(const(char)* pass, int passlen, const(ubyte)* salt, int saltlen, int iter,
    const(void)* digest, int keylen, ubyte* output);
  int RAND_bytes(ubyte* buffer, int num);
}

final class OpensslPasswordHasher : IPasswordHasher {
  private enum scheme = "pbkdf2-sha256";
  private enum maxIterations = 100_000_000;
  /// OWASP recommendation for PBKDF2-HMAC-SHA256 (2023+).
  enum defaultIterations = 600_000;
  private int iterations;

  this(int iterations = defaultIterations) {
    enforce(iterations > 0 && iterations <= maxIterations, "Invalid PBKDF2 iteration count");
    this.iterations = iterations;
  }

  string hash(string password) {
    auto salt = randomBytes(16);
    return format("%s$%d$%s$%s", scheme, iterations, Base64.encode(salt), Base64.encode(derive(password, salt, iterations)));
  }

  bool verify(string password, string stored) {
    auto parts = stored.split("$");
    if (parts.length != 4 || parts[0] != scheme)
      return false;
    try {
      immutable rounds = parts[1].to!int;
      if (rounds <= 0 || rounds > maxIterations)
        return false;
      auto salt = Base64.decode(parts[2]).idup;
      auto expected = Base64.decode(parts[3]);
      if (salt.length == 0)
        return false;
      return sameBytes(derive(password, salt, rounds), expected);
    } catch (Exception)
      return false;
  }

  string randomSecret() {
    return Base64URLNoPadding.encode(randomBytes(32)).idup;
  }
}

private immutable(ubyte)[] randomBytes(int count) @trusted {
  auto buffer = new ubyte[count];
  enforce(RAND_bytes(&buffer[0], count) == 1, "No secure random numbers available");
  return buffer.idup;
}

/// Inside a request the derivation runs on a worker thread, otherwise the
/// event loop (and every other request) would stand still meanwhile.
private const(ubyte)[] derive(string password, immutable(ubyte)[] salt, int rounds) @trusted {
  if (Task.getThis() == Task.init)
    return pbkdf2(password, salt, rounds);
  return async(&pbkdf2, password, salt, rounds).getResult();
}

private immutable(ubyte)[] pbkdf2(string password, immutable(ubyte)[] salt, int rounds) @trusted {
  enum keyLength = 32;
  auto key = new ubyte[keyLength];
  // toStringz: an empty password must not become a null pointer.
  enforce(PKCS5_PBKDF2_HMAC(password.toStringz, password.length.to!int, &salt[0], salt.length.to!int, rounds,
      EVP_sha256(), keyLength, &key[0]) == 1, "Password hashing failed");
  return key.idup;
}

/// Comparison without early exit, so timing reveals nothing about the hash.
private bool sameBytes(const(ubyte)[] a, const(ubyte)[] b) pure nothrow {
  uint diff = a.length != b.length;
  foreach (i; 0 .. min(a.length, b.length))
    diff |= a[i] ^ b[i];
  return diff == 0;
}

///
unittest {
  import std.digest : LetterCase, toHexString;

  auto hasher = new OpensslPasswordHasher(1000);
  auto h = hasher.hash("correct horse ümläut");
  assert(h.split("$")[1] == "1000");
  assert(hasher.verify("correct horse ümläut", h));
  assert(!hasher.verify("correct horse umlaut", h));
  assert(!hasher.verify("", h));
  assert(hasher.hash("x") != hasher.hash("x")); // own salt per hash
  assert(!hasher.verify("x", "plaintext") && !hasher.verify("x", "pbkdf2-sha256$x$y$z"));
  assert(hasher.randomSecret() != hasher.randomSecret() && hasher.randomSecret().length == 43);

  // RFC 6070 style vector: PBKDF2-HMAC-SHA256("password", "salt", 1, 32)
  assert(pbkdf2("password", cast(immutable(ubyte)[]) "salt", 1).toHexString!(LetterCase.lower)
      == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
}
