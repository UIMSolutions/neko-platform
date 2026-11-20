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
enum sitesCollection = "sites";
enum filesCollection = "files";
enum ipRulesCollection = "iprules";

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
  /// Site keys the account is limited to; missing or empty = every site.
  @optional string[] sites;
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
  /// The catalogue the rights were decided on; missing = the first version.
  @optional string[] knownRights;
}

struct SiteContentRecord {
  string language;
  @optional string title;
  @optional string tagline;
  @optional string body;
}

struct SiteRecord {
  string key;
  string name;
  @optional string[] hosts;
  /// The first one is the default language.
  @optional string[] languages;
  @optional SiteContentRecord[] content;
  @optional bool isDefault;
  string createdAt;
  string modifiedAt;
}

/// Metadata of a file; the content is <dataDir>/<domain>/files/<site>/<id>.
struct FileRecord {
  string id;
  string site;
  string name;
  long size;
  @optional string sha256;
  @optional string description;
  @optional bool isPublic;
  @optional string uploadedBy;
  string createdAt;
  string modifiedAt;
  /// Informational; the content type is derived from the name when read.
  @optional string contentType;
}

/// An entry of the IP allow / deny list.
struct IpRuleRecord {
  string id;
  /// CIDR or single address.
  string network;
  /// "allow" | "deny"
  string action;
  /// "all" | "admin" | "api"
  string scope_;
  @optional string note;
  @optional string createdBy;
  string createdAt;
}
