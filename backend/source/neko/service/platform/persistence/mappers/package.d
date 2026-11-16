/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Converters between stored records and domain entities.
module neko.service.platform.persistence.mappers;

import std.conv : to;
import std.datetime.systime : SysTime;
import neko.service.platform.domain;
import neko.service.platform.persistence.records;

@safe:

private string timeToText(SysTime t) {
  return t == SysTime.init ? "" : t.toUTC.toISOExtString;
}

private SysTime textToTime(string text) {
  if (text.length == 0)
    return SysTime.init;
  try
    return SysTime.fromISOExtString(text);
  catch (Exception)
    return SysTime.init;
}

private E toEnum(E)(string text, E fallback) {
  E value;
  return tryParseEnum!E(text, value) ? value : fallback;
}

private SecurityDomain toDomain(string text) {
  SecurityDomain d;
  if (!tryParseSecurityDomain(text, d))
    throw new ValidationException("Stored record has unknown security domain '" ~ text ~ "'");
  return d;
}

ServiceRecord toRecord(const PlatformService s) {
  return ServiceRecord(s.id.value, s.name.value, s.description, s.classification.label,
    s.endpoint.baseUrl, s.endpoint.healthPath, s.status.to!string, s.health.to!string,
    timeToText(s.lastCheckedAt), timeToText(s.createdAt), timeToText(s.modifiedAt));
}

PlatformService toEntity(const ServiceRecord r) {
  PlatformService s;
  s.id = ServiceId(r.id);
  s.name = ServiceName(r.name);
  s.description = r.description;
  s.classification = toDomain(r.classification);
  s.endpoint = ServiceEndpoint(r.baseUrl, r.healthPath);
  s.status = toEnum(r.status, ServiceStatus.registered);
  s.health = toEnum(r.health, HealthState.unknown);
  s.lastCheckedAt = textToTime(r.lastCheckedAt);
  s.createdAt = textToTime(r.createdAt);
  s.modifiedAt = textToTime(r.modifiedAt);
  return s;
}

TransferRecord toRecord(const TransferPackage t) {
  return TransferRecord(t.id.value, t.name, t.direction.to!string, t.sourceDomain.label,
    t.targetDomain.label, t.status.to!string, t.payload, t.checksum, t.reason, t.createdBy,
    timeToText(t.createdAt));
}

TransferPackage toEntity(const TransferRecord r) {
  TransferPackage t;
  t.id = TransferId(r.id);
  t.name = r.name;
  t.direction = toEnum(r.direction, TransferDirection.inbound);
  t.sourceDomain = toDomain(r.sourceDomain);
  t.targetDomain = toDomain(r.targetDomain);
  t.status = toEnum(r.status, TransferStatus.rejected);
  t.payload = r.payload;
  t.checksum = r.checksum;
  t.reason = r.reason;
  t.createdBy = r.createdBy;
  t.createdAt = textToTime(r.createdAt);
  return t;
}

///
unittest {
  import std.datetime.systime : Clock;

  PlatformService s;
  s.id = ServiceId("1");
  s.name = ServiceName("alpha");
  s.classification = SecurityDomain.confidential;
  s.status = ServiceStatus.suspended;
  s.createdAt = SysTime.fromISOExtString("2026-11-16T10:00:00Z");
  auto back = toEntity(toRecord(s));
  assert(back.name == s.name && back.status == s.status && back.classification == s.classification);
  assert(back.createdAt == s.createdAt);
}
