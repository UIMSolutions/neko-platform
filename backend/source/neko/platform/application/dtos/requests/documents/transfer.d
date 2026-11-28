/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The exchange format of a transfer package ("neko-transfer/1"): the file
/// that is carried from one domain to the next (e.g. via a data diode).
module neko.platform.application.dtos.requests.documents.transfer;

import std.datetime.systime : SysTime;
import vibe.data.json;
import neko.platform.application.dtos.requests.documents;
import neko.platform.application.dtos.responses : isoTime;
import neko.platform.domain.entities.transfer;
import neko.platform.domain.exceptions;
import neko.platform.domain.types.id;
import neko.platform.domain.enumerations.status;
import neko.platform.domain.enumerations.security;

@safe:

enum transferFormat = "neko-transfer/1";

Json toDocument(const TransferPackage pkg) {
  auto doc = Json.emptyObject;
  doc["format"] = transferFormat;
  doc["id"] = pkg.id.value;
  doc["name"] = pkg.name;
  doc["sourceDomain"] = pkg.sourceDomain.label;
  doc["targetDomain"] = pkg.targetDomain.label;
  doc["createdBy"] = pkg.createdBy;
  doc["createdAt"] = isoTime(pkg.createdAt);
  doc["payload"] = pkg.payload;
  doc["checksum"] = pkg.checksum;
  return doc;
}

/// Parse a transfer document into an (inbound) package. Structural errors
/// raise a ValidationException; policy and checksum are checked by the caller.
TransferPackage fromDocument(string text) {
  Json doc;
  try
    doc = parseJsonString(text);
  catch (Exception e)
    throw new ValidationException("Transfer document is not valid JSON: " ~ e.msg);
  if (doc.type != Json.Type.object)
    throw new ValidationException("Transfer document must be a JSON object");

  string field(string key, bool required = true) {
    auto v = key in doc;
    if (v is null || v.type != Json.Type.string) {
      if (required)
        throw new ValidationException("Transfer document lacks the string field '" ~ key ~ "'");
      return "";
    }
    return v.get!string;
  }

  if (field("format") != transferFormat)
    throw new ValidationException("Unsupported transfer format '" ~ field("format") ~ "'");

  TransferPackage pkg;
  pkg.id = TransferId(field("id"));
  pkg.name = field("name");
  if (!tryParseSecurityDomain(field("sourceDomain"), pkg.sourceDomain))
    throw new ValidationException("Unknown source domain '" ~ field("sourceDomain") ~ "'");
  if (!tryParseSecurityDomain(field("targetDomain"), pkg.targetDomain))
    throw new ValidationException("Unknown target domain '" ~ field("targetDomain") ~ "'");
  pkg.createdBy = field("createdBy", false);
  auto created = field("createdAt", false);
  if (created.length > 0) {
    try
      pkg.createdAt = SysTime.fromISOExtString(created);
    catch (Exception)
      throw new ValidationException("Invalid createdAt '" ~ created ~ "'");
  }
  pkg.payload = field("payload");
  pkg.checksum = field("checksum");
  if (pkg.id.isEmpty)
    throw new ValidationException("Transfer document has an empty id");
  pkg.direction = TransferDirection.inbound;
  return pkg;
}
///
unittest {
  TransferPackage pkg;
  pkg.id = TransferId("t1");
  pkg.name = "n";
  pkg.sourceDomain = SecurityDomain.open;
  pkg.targetDomain = SecurityDomain.secret;
  pkg.payload = "data";
  pkg.checksum = TransferPolicy.seal(pkg);

  auto back = fromDocument(toDocument(pkg).toString);
  assert(back.id == pkg.id && back.payload == "data" && back.direction == TransferDirection.inbound);
  assert(TransferPolicy.seal(back) == pkg.checksum);

  bool invalid;
  try
    fromDocument(`{"format":"other/1"}`);
  catch (ValidationException)
    invalid = true;
  assert(invalid);
}
