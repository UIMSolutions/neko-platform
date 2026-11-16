/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.application.dtos.responses;

import std.conv : to;
import std.datetime.systime : SysTime;
import neko.service.platform.domain;

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

/// ISO 8601 (UTC) or "" for unset timestamps.
string isoTime(SysTime time) {
  return time == SysTime.init ? "" : time.toUTC.toISOExtString;
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
