/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Pure domain services: the security-domain rules of the platform.
module neko.platform.domain.services.policies;

import std.digest : toHexString, LetterCase;
import std.digest.sha : sha256Of;
import neko.platform.domain.entities;
import neko.platform.domain.enumerations;
import neko.platform.domain.exceptions;

@safe:

/// Which services a platform instance may host.
struct ClassificationPolicy {
  SecurityDomain platformDomain;

  /// A platform must never host data classified above its own domain.
  void requireHostable(SecurityDomain classification) const {
    if (classification > platformDomain)
      throw new PolicyViolationException("A " ~ platformDomain.label ~ " platform cannot host "
          ~ classification.label ~ " services");
  }
}

/// One-way transfer rules ("no write-down"): data only moves to higher domains.
struct TransferPolicy {
  SecurityDomain platformDomain;

  void requireExportTo(SecurityDomain target) const {
    if (!platformDomain.canExport)
      throw new PolicyViolationException("Export is disabled in the " ~ platformDomain.label ~ " domain");
    if (target <= platformDomain)
      throw new PolicyViolationException("Data may only be exported to a higher domain (from "
          ~ platformDomain.label ~ " to " ~ target.label ~ " is a downward or lateral flow)");
  }

  /// Validates an inbound package; throws on any violation, including tampering.
  void requireImportable(const TransferPackage pkg) const {
    if (!platformDomain.canImport)
      throw new PolicyViolationException("Import is disabled in the " ~ platformDomain.label ~ " domain");
    if (pkg.targetDomain != platformDomain)
      throw new PolicyViolationException("Package is addressed to the " ~ pkg.targetDomain.label
          ~ " domain, this is " ~ platformDomain.label);
    if (pkg.sourceDomain >= platformDomain)
      throw new PolicyViolationException("Packages from the " ~ pkg.sourceDomain.label
          ~ " domain cannot be imported into " ~ platformDomain.label);
    if (pkg.checksum != seal(pkg))
      throw new IntegrityException("Checksum mismatch: package '" ~ pkg.id.value ~ "' was modified in transit");
  }

  /// SHA-256 over every field that must not change between export and import.
  /// A length prefix per field prevents ambiguity ("ab"+"c" vs. "a"+"bc").
  static string seal(const TransferPackage pkg) {
    import std.conv : to;

    string canonical;
    foreach (part; [pkg.id.value, pkg.name, pkg.sourceDomain.label, pkg.targetDomain.label,
        pkg.createdBy, pkg.payload])
      canonical ~= part.length.to!string ~ ":" ~ part ~ ";";
    return sha256Of(canonical).toHexString!(LetterCase.lower).idup;
  }
}
///
unittest {
  auto hosting = ClassificationPolicy(SecurityDomain.restricted);
  hosting.requireHostable(SecurityDomain.open);
  bool refused;
  try
    hosting.requireHostable(SecurityDomain.secret);
  catch (PolicyViolationException)
    refused = true;
  assert(refused);

  TransferPackage pkg;
  pkg.name = "report";
  pkg.sourceDomain = SecurityDomain.open;
  pkg.targetDomain = SecurityDomain.confidential;
  pkg.payload = `{"a":1}`;
  pkg.checksum = TransferPolicy.seal(pkg);

  TransferPolicy(SecurityDomain.open).requireExportTo(SecurityDomain.confidential);
  TransferPolicy(SecurityDomain.confidential).requireImportable(pkg);

  // downward export
  refused = false;
  try
    TransferPolicy(SecurityDomain.confidential).requireExportTo(SecurityDomain.open);
  catch (PolicyViolationException)
    refused = true;
  assert(refused);

  // wrong recipient
  refused = false;
  try
    TransferPolicy(SecurityDomain.secret).requireImportable(pkg);
  catch (PolicyViolationException)
    refused = true;
  assert(refused);

  // tampered payload
  pkg.payload = `{"a":2}`;
  bool tampered;
  try
    TransferPolicy(SecurityDomain.confidential).requireImportable(pkg);
  catch (IntegrityException)
    tampered = true;
  assert(tampered);
}
