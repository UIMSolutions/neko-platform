/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A data package moved between two security domains (one-way, upwards).
module neko.platform.domain.entities.transfer;

import std.datetime.systime : SysTime;
import neko.platform.domain.enumerations;
import neko.platform.domain.types;

@safe:

struct TransferPackage {
  TransferId id;
  string name;
  TransferDirection direction;
  SecurityDomain sourceDomain;
  SecurityDomain targetDomain;
  TransferStatus status;
  /// Payload as text (JSON, CSV, …); binary data is expected base64-encoded.
  string payload;
  /// Hex SHA-256 over the sealed fields (see TransferPolicy.seal).
  string checksum;
  /// Why an inbound package was rejected.
  string reason;
  string createdBy;
  SysTime createdAt;

  size_t size() const pure nothrow {
    return payload.length;
  }
}
///
unittest {
  import std.datetime.systime : Clock;

  auto now = Clock.currTime;
  TransferPackage p;
  p.name = "test";
  p.direction = TransferDirection.outbound;
  p.sourceDomain = SecurityDomain.open;
  p.targetDomain = SecurityDomain.restricted;
  p.status = TransferStatus.exported;
  p.payload = "{}";
  p.checksum = "dummy";
  p.reason = "";
  p.createdBy = "tester";
  p.createdAt = now;

  assert(p.size() == p.payload.length);
}
