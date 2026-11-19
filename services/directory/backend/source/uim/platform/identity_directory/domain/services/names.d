/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Naming, e-mail, URN, scope and attribute-name rules.
module neko.directory.domain.services.names;

import std.ascii : isAlpha, isAlphaNum, isDigit;
import std.uni : icmp;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Case-insensitive name equality (user names, group names, attribute names).
bool sameName(string a, string b) {
  return icmp(a.strip, b.strip) == 0;
}

/// A display name: 1..max characters, no control characters.
void validateDisplayName(string label, string value, size_t max = 120) {
  auto v = value.strip;
  validate(v.length > 0, label ~ " is required");
  validate(v.length <= max, label ~ " must not exceed " ~ max.to!string ~ " characters");
  validate(!v.any!(c => c < 0x20), label ~ " must not contain control characters");
}

/// A user name: 1..256 characters out of letters, digits and . _ - @ + '.
bool isUserName(string value) pure {
  if (value.length == 0 || value.length > 256)
    return false;
  foreach (c; value)
    if (!(isAlphaNum(c) || ".-_@+'".canFind(c)))
      return false;
  return true;
}

/// Very small e-mail check: local@domain.tld without blanks.
bool isEmail(string value) pure {
  auto at = value.indexOf('@');
  if (at <= 0 || value.canFind(" ") || value.count('@') != 1)
    return false;
  auto domain = value[at + 1 .. $];
  auto dot = domain.lastIndexOf('.');
  return dot > 0 && dot < cast(ptrdiff_t) domain.length - 1;
}

/// A schema URN: "urn:" followed by at least two ":"-separated parts.
bool isUrn(string value) pure {
  if (!value.startsWith("urn:") || value.canFind(" ") || value.endsWith(":"))
    return false;
  return value.split(":").length >= 3;
}

/// A SCIM attribute name: ALPHA *(ALPHA / DIGIT / "-" / "_"), at most 64 characters.
bool isAttributeName(string value) pure {
  if (value.length == 0 || value.length > 64 || !isAlpha(value[0]))
    return false;
  return value.all!(c => isAlphaNum(c) || c == '-' || c == '_');
}

/// An OAuth scope: printable characters without blanks, quotes or backslashes.
bool isScope(string value) pure {
  return value.length > 0 && value.length <= 128 && value.all!(c => c > 0x20 && c < 0x7f && c != '"' && c != '\\');
}

/// Optional http(s) URL.
bool isOptionalUrl(string value) pure {
  auto v = value.strip;
  return v.length == 0 || ((v.startsWith("https://") || v.startsWith("http://")) && !v.canFind(" ") && v.length > 8);
}

/// Trimmed, non-empty, de-duplicated (case-insensitive) names in input order.
string[] normalizedNames(const string[] names) {
  string[] result;
  foreach (n; names) {
    auto v = n.strip;
    if (v.length > 0 && !result.any!(r => sameName(r, v)))
      result ~= v;
  }
  return result;
}

///
unittest {
  assert(sameName("Jane.Doe", " jane.doe "));
  assert(isUserName("jane.doe@example.com") && isUserName("o'neil") && !isUserName("jane doe") && !isUserName(""));
  assert(isEmail("jane@example.com") && !isEmail("jane@") && !isEmail("jane.example.com"));
  assert(isUrn("urn:ietf:params:scim:schemas:extension:enterprise:2.0:User") && !isUrn("urn:x") && !isUrn("http://x"));
  assert(isAttributeName("costCenter") && isAttributeName("cost_center-2") && !isAttributeName("2x") && !isAttributeName("a.b"));
  assert(isScope("directory.read") && isScope("uaa.resource") && !isScope("a b"));
  assert(isOptionalUrl("") && isOptionalUrl("https://x.io/me") && !isOptionalUrl("ftp://x"));
  assert(normalizedNames([" a", "B", "A", "", "b "]) == ["a", "B"]);
}
