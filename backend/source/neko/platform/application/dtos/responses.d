/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.responses;

import std.conv : to;
import std.datetime.date : DateTime;
import std.datetime.systime : SysTime;
import neko.platform.domain;

@safe:

struct ServiceDto {
  string id;
  string name;
  string description;
  string classification;
  string baseUrl;
  string healthPath;
  string status;
  string health;
  string lastCheckedAt;
  string createdAt;
  string modifiedAt;
}

struct TransferDto {
  string id;
  string name;
  string direction;
  string sourceDomain;
  string targetDomain;
  string status;
  string checksum;
  long size;
  string reason;
  string createdBy;
  string createdAt;
}

struct OverviewDto {
  string domain;
  bool canExport;
  bool canImport;
  string[] exportTargets;
  long serviceCount;
  long activeServices;
  long servicesDown;
  long transferCount;
  long outboundTransfers;
  long inboundTransfers;
  long rejectedTransfers;
  string environment;
}

/// A web user account; the password hash never leaves the application layer.
struct UserDto {
  string id;
  string userName;
  string displayName;
  string email;
  string role;
  bool active;
  string createdAt;
  string modifiedAt;
  string lastLoginAt;
  string passwordChangedAt;

  bool isAdmin() const pure nothrow {
    return role == "admin";
  }

  string label() const pure nothrow {
    return displayName.length > 0 ? displayName : userName;
  }
}

/// ISO 8601 in UTC with fixed millisecond precision ("2026-11-16T21:25:30.885Z"),
/// so timestamps also sort correctly as text; "" for unset timestamps.
string isoTime(SysTime time) {
  import std.datetime.date : DateTime;
  import std.format : format;

  if (time == SysTime.init)
    return "";
  auto utc = time.toUTC;
  return (cast(DateTime) utc).toISOExtString ~ format(".%03dZ", utc.fracSecs.total!"msecs");
}

///
unittest {
  import std.datetime.timezone : UTC;
  import core.time : usecs;

  auto t = SysTime(DateTime(2026, 11, 16, 21, 25, 30), 885_407.usecs, UTC());
  assert(isoTime(t) == "2026-11-16T21:25:30.885Z");
  assert(isoTime(SysTime(DateTime(2026, 1, 2, 3, 4, 5), UTC())) == "2026-01-02T03:04:05.000Z");
  assert(isoTime(SysTime.init) == "");
}

ServiceDto toDto(const PlatformService s) {
  ServiceDto d;
  d.id = s.id.value;
  d.name = s.name.value;
  d.description = s.description;
  d.classification = s.classification.label;
  d.baseUrl = s.endpoint.baseUrl;
  d.healthPath = s.endpoint.healthPath;
  d.status = s.status.to!string;
  d.health = s.health.to!string;
  d.lastCheckedAt = isoTime(s.lastCheckedAt);
  d.createdAt = isoTime(s.createdAt);
  d.modifiedAt = isoTime(s.modifiedAt);
  return d;
}

TransferDto toDto(const TransferPackage t) {
  TransferDto d;
  d.id = t.id.value;
  d.name = t.name;
  d.direction = t.direction.to!string;
  d.sourceDomain = t.sourceDomain.label;
  d.targetDomain = t.targetDomain.label;
  d.status = t.status.to!string;
  d.checksum = t.checksum;
  d.size = cast(long) t.size;
  d.reason = t.reason;
  d.createdBy = t.createdBy;
  d.createdAt = isoTime(t.createdAt);
  return d;
}

UserDto toDto(const UserAccount a) {
  UserDto d;
  d.id = a.id.value;
  d.userName = a.userName.value;
  d.displayName = a.displayName;
  d.email = a.email;
  d.role = a.role.to!string;
  d.active = a.active;
  d.createdAt = isoTime(a.createdAt);
  d.modifiedAt = isoTime(a.modifiedAt);
  d.lastLoginAt = isoTime(a.lastLoginAt);
  d.passwordChangedAt = isoTime(a.passwordChangedAt);
  return d;
}
