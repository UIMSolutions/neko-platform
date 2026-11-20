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
enum usersCollection = "users";
enum rolesCollection = "roles";

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

struct UserRecord {
  string id;
  string userName;
  @optional string displayName;
  @optional string email;
  /// Role names. Documents written before roles existed only have `role`.
  @optional string[] roles;
  /// Before roles: "viewer" | "admin". Still written (the first role) so an
  /// older binary can read the document.
  @optional string role;
  bool active;
  string passwordHash;
  string createdAt;
  string modifiedAt;
  @optional string lastLoginAt;
  @optional string passwordChangedAt;
}

struct RoleRecord {
  string name;
  @optional string label;
  @optional string description;
  /// Access right keys ("users.read").
  @optional string[] rights;
  @optional bool builtIn;
  string createdAt;
  string modifiedAt;
}
