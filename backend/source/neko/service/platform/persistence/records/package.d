/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Technical storage models (schema of the stored JSON documents). Changing
/// a field here is a data migration — keep names stable.
module neko.platform.persistence.records;

import vibe.data.serialization : optional;

@safe:

enum servicesCollection = "services";
enum transfersCollection = "transfers";

struct ServiceRecord {
  string id;
  string name;
  @optional string description;
  string classification;
  @optional string baseUrl;
  @optional string healthPath;
  string status;
  @optional string health;
  @optional string lastCheckedAt;
  string createdAt;
  string modifiedAt;
}

struct TransferRecord {
  string id;
  string name;
  string direction;
  string sourceDomain;
  string targetDomain;
  string status;
  string payload;
  string checksum;
  @optional string reason;
  @optional string createdBy;
  string createdAt;
}
