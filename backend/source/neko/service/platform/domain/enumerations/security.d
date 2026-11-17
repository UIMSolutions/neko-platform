/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Security domains (classification levels) of the platform.
///
/// Every platform instance runs in exactly one domain. Data may only flow
/// upwards (open → restricted → confidential → secret), never downwards.
module neko.service.platform.domain.enumerations.security;

import std.conv : to;
import std.string : toLower, strip;

@safe:

enum SecurityDomain : ubyte {
  open = 0,
  restricted = 1,
  confidential = 2,
  secret = 3
}

/// Lower-case name used in APIs, configuration and file formats.
string label(SecurityDomain domain) pure nothrow {
  final switch (domain) {
  case SecurityDomain.open:
    return "open";
  case SecurityDomain.restricted:
    return "restricted";
  case SecurityDomain.confidential:
    return "confidential";
  case SecurityDomain.secret:
    return "secret";
  }
}

/// Parse "open", "Restricted", "2", … ; "offen" is accepted for older data.
bool tryParseSecurityDomain(string text, out SecurityDomain domain) pure {
  switch (text.strip.toLower) {
  case "open", "offen", "0":
    domain = SecurityDomain.open;
    return true;
  case "restricted", "1":
    domain = SecurityDomain.restricted;
    return true;
  case "confidential", "2":
    domain = SecurityDomain.confidential;
    return true;
  case "secret", "3":
    domain = SecurityDomain.secret;
    return true;
  default:
    return false;
  }
}

/// A domain can export if a higher domain exists to receive the data.
bool canExport(SecurityDomain domain) pure nothrow {
  return domain != SecurityDomain.max;
}

/// All domains strictly below `domain` (valid import sources).
bool canExportTo(SecurityDomain domain, SecurityDomain target) pure nothrow {
  return domain < target;
}

/// A domain can import if a lower domain exists that may send data.
bool canImport(SecurityDomain domain) pure nothrow {
  return domain != SecurityDomain.min;
}

/// All domains strictly below `domain` (valid import sources).
bool canImportFrom(SecurityDomain domain, SecurityDomain source) pure nothrow {
  return domain > source;
}

/// All domains strictly above `domain` (valid export targets).
SecurityDomain[] higherDomains(SecurityDomain domain) pure nothrow {
  SecurityDomain[] result;
  foreach (value; cast(int) domain + 1 .. cast(int) SecurityDomain.max + 1)
    result ~= cast(SecurityDomain) value;
  return result;
}
///
unittest {
  SecurityDomain d;
  assert(tryParseSecurityDomain("Confidential", d) && d == SecurityDomain.confidential);
  assert(tryParseSecurityDomain("offen", d) && d == SecurityDomain.open);
  assert(!tryParseSecurityDomain("top-secret", d));

  assert(SecurityDomain.open.canExport && !SecurityDomain.open.canImport);
  assert(!SecurityDomain.secret.canExport && SecurityDomain.secret.canImport);
  assert(SecurityDomain.restricted.higherDomains == [SecurityDomain.confidential, SecurityDomain.secret]);
  assert(SecurityDomain.secret.higherDomains.length == 0);
  assert(SecurityDomain.secret.label == "secret");
}
