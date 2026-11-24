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
/// Sites of earlier versions (read once by the migration, then removed).
enum legacySitesCollection = "sites";
enum filesCollection = "files";
enum ipRulesCollection = "iprules";
enum landscapeCollection = "landscape";
enum directoriesCollection = "directories";
enum subaccountsCollection = "subaccounts";
enum plansCollection = "serviceplans";
enum usageCollection = "usage";
enum globalAccountsCollection = "globalaccounts";

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
  /// The catalogue the rights were decided on; missing = the first version.
  @optional string[] knownRights;
}

/// Metadata of a file; the content is <dataDir>/<domain>/files/<subaccount>/<id>.
struct FileRecord {
  string id;
  /// Missing in documents of earlier versions, which name a `site` instead
  /// (see persistence.migrations).
  @optional string subaccount;
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
  /// Earlier versions: the site whose library held the file.
  @optional string site;
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

struct EntitlementRecord {
  string plan;
  /// -1 = unlimited
  long quota;
}

struct RoleCollectionRecord {
  string name;
  @optional string description;
  @optional string[] rights;
  @optional string[] members;
}

/// The one global account (document "global").
struct GlobalAccountRecord {
  string name;
  @optional string subdomainPrefix;
  @optional string subdomainPattern;
  @optional string contract;
  @optional string currency;
  @optional string costCenter;
  @optional string[] admins;
  @optional EntitlementRecord[] entitlements;
  @optional RoleCollectionRecord[] roleCollections;
  @optional string modifiedAt;
}

struct DirectoryRecord {
  string key;
  string name;
  @optional string description;
  @optional string parent;
  @optional bool manageEntitlements;
  @optional bool manageAuthorizations;
  @optional string costCenter;
  @optional string owner;
  @optional EntitlementRecord[] entitlements;
  @optional RoleCollectionRecord[] roleCollections;
  string createdAt;
  string modifiedAt;
}

struct SpaceRecord {
  string key;
  @optional string name;
  @optional string description;
  @optional string createdAt;
}

struct TenantRecord {
  string key;
  @optional string name;
  @optional string description;
  @optional bool isDefault;
  @optional SpaceRecord[] spaces;
  @optional string createdAt;
  @optional string modifiedAt;
}

struct SubaccountRecord {
  string key;
  string name;
  @optional string description;
  @optional string directory;
  string region;
  string subdomain;
  @optional string purpose;
  string stage;
  string domain;
  @optional string costCenter;
  @optional bool betaFeatures;
  @optional EntitlementRecord[] entitlements;
  @optional RoleCollectionRecord[] roleCollections;
  string createdAt;
  string modifiedAt;
  @optional string[] admins;
  @optional string[] members;
  @optional string[] services;
  @optional TenantRecord[] tenants;
  @optional RecoveryRecord recovery;
}

struct RecoveryEventRecord {
  string at;
  string kind;
  @optional string from;
  @optional string to;
  @optional string actor;
  @optional string reason;
  @optional long minutes;
  @optional bool success = true;
}

/// Disaster recovery of a subaccount; missing = disabled.
struct RecoveryRecord {
  @optional bool enabled;
  @optional string secondaryRegion;
  /// "backup-restore" | "pilot-light" | "warm-standby" | "active-active"
  @optional string strategy;
  @optional long rpoMinutes = 15;
  @optional long rtoMinutes = 60;
  @optional bool failedOver;
  @optional string lastFailoverAt;
  @optional string lastDrillAt;
  @optional RecoveryEventRecord[] history;
}

/// A global account of the instance (collection "globalaccounts" in the
/// instance's data directory).
struct GlobalAccountEntryRecord {
  string key;
  string name;
  @optional string[] hosts;
  @optional string dataDir;
  @optional bool isDefault;
  @optional string description;
  @optional string createdAt;
  @optional string modifiedAt;
}

struct ServicePlanRecord {
  string key;
  string service;
  string plan;
  @optional string description;
  string unit;
  double unitSize;
  double price;
  /// "none" | "requests" | "egressBytes" | "storageBytes"
  string meter;
}

/// Usage of a subaccount in a month (document "<month>|<subaccount>").
struct UsageDocument {
  string month;
  string subaccount;
  long requests;
  long bytesOut;
  long peakStorageBytes;
}
