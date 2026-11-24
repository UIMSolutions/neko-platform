/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Host names of requests (global accounts claim them).
module neko.platform.domain.types.host;

import std.algorithm : all, countUntil, endsWith;
import std.ascii : isAlphaNum;
import std.string : strip, toLower;
import neko.platform.domain.exceptions;

@safe:

/// "Example.org:8080" → "example.org", "[::1]:8080" → "[::1]"; "" if empty.
string normalizeHost(string hostHeader) pure {
  auto h = hostHeader.strip.toLower;
  if (h.length && h[0] == '[') {
    auto close = h.countUntil(']');
    return close > 0 ? h[0 .. close + 1] : h;
  }
  auto colon = h.countUntil(':');
  if (colon >= 0)
    h = h[0 .. colon];
  while (h.endsWith("."))
    h = h[0 .. $ - 1];
  return h;
}

/// A host name (lower case, without port), or ValidationException.
string validHost(string name) pure {
  auto h = normalizeHost(name);
  if (h.length == 0 || h.length > 253 || h[0] == '.' || h[0] == '-'
      || !h.all!(c => (c.isAlphaNum && c < 0x80) || c == '.' || c == '-' || c == '[' || c == ']' || c == ':'))
    throw new ValidationException("'" ~ name.strip ~ "' is not a host name (e.g. www.example.org)");
  return h;
}

///
unittest {
  assert(normalizeHost("[::1]:8080") == "[::1]" && normalizeHost("Example.org.") == "example.org");
  assert(validHost("Shop.Example.org:8080") == "shop.example.org");
  bool failed;
  try
    validHost("bad host");
  catch (ValidationException)
    failed = true;
  assert(failed);
}
