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
  /// Role names.
  string[] roles;
  /// Effective access right keys: the union of the rights of the roles.
  string[] rights;
  /// Site keys the account is limited to; empty = every site.
  string[] sites;
  bool active;
  string createdAt;
  string modifiedAt;
  string lastLoginAt;
  string passwordChangedAt;

  bool hasRole(string name) const pure nothrow {
    import std.algorithm : canFind;

    return roles.canFind(name);
  }

  /// True if the account holds the right ("users.manage").
  bool can(string right) const pure nothrow {
    import std.algorithm : canFind;

    return rights.canFind(right);
  }

  string label() const pure nothrow {
    return displayName.length > 0 ? displayName : userName;
  }

  bool allSites() const pure nothrow {
    return sites.length == 0;
  }

  bool mayAccessSite(string key) const pure nothrow {
    import std.algorithm : canFind;

    return allSites || sites.canFind(key);
  }
}

/// A role and the access rights it grants.
struct RoleDto {
  string name;
  string label;
  string description;
  /// Access right keys.
  string[] rights;
  bool builtIn;
  /// The administrator role: always every right, not editable.
  bool locked;
  /// Number of accounts holding the role.
  long members;
  string createdAt;
  string modifiedAt;

  bool grants(string right) const pure nothrow {
    import std.algorithm : canFind;

    return rights.canFind(right);
  }
}

/// One entry of the access right catalogue.
struct AccessRightDto {
  string key;
  string label;
  string description;
  string area;
}

struct SiteContentDto {
  string language;
  string title;
  string tagline;
  /// Plain text; blank lines separate paragraphs.
  string body;

  /// The paragraphs of `body`.
  string[] paragraphs() const pure {
    import std.algorithm : filter, map, splitter;
    import std.array : array, replace;
    import std.string : strip;

    return body.replace("\r\n", "\n").splitter("\n\n").map!(p => p.strip).filter!(p => p.length > 0).array;
  }
}

/// A site (tenant) with its languages and home page content.
struct SiteDto {
  string key;
  string name;
  string[] hosts;
  /// The first one is the default language.
  string[] languages;
  string defaultLanguage;
  bool isDefault;
  /// Per language (only the site's languages).
  SiteContentDto[] content;
  /// Files and their bytes.
  long files;
  long bytes;
  string createdAt;
  string modifiedAt;

  SiteContentDto contentFor(string language) const pure nothrow {
    foreach (c; content)
      if (c.language == language)
        return c;
    return SiteContentDto(language);
  }

  bool hasContent(string language) const pure nothrow {
    auto c = contentFor(language);
    return c.title.length > 0 || c.body.length > 0;
  }
}

/// Metadata of a file in a site's library.
struct FileDto {
  string id;
  string site;
  string name;
  string contentType;
  /// "document" | "image" | "audio" | "video" | "archive" | "other"
  string kind;
  long size;
  string sha256;
  string description;
  bool isPublic;
  /// Shown in place by browsers (raster images, audio, video, PDF).
  bool inline;
  string uploadedBy;
  string createdAt;
  string modifiedAt;

  /// Address on the public site (only served while the file is public).
  string publicUrl() const pure {
    import std.uri : encodeComponent;

    return "/media/" ~ site ~ "/" ~ id ~ "/" ~ (() @trusted => encodeComponent(name))();
  }
}

/// A file and how to get its content (see IBlobStore.localPath).
struct FileContent {
  FileDto file;
  /// Local path to stream from; "" → `data`.
  string localPath;
  immutable(ubyte)[] data;
}

struct SiteUsageDto {
  string site;
  string name;
  long files;
  long bytes;
}

struct StorageDto {
  SiteUsageDto[] sites;
  long files;
  long bytes;
  /// Free bytes on the volume; -1 if unknown.
  long available;
  string location;
}

/// What the public home page of a site shows.
struct SitePageDto {
  SiteDto site;
  /// Language of `content`.
  string language;
  SiteContentDto content;
  /// Public files of the site, newest first.
  FileDto[] images;
  /// Audio and video.
  FileDto[] media;
  /// Everything else.
  FileDto[] documents;
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
  d.roles = a.roles.dup;
  d.sites = a.sites.dup;
  d.active = a.active;
  d.createdAt = isoTime(a.createdAt);
  d.modifiedAt = isoTime(a.modifiedAt);
  d.lastLoginAt = isoTime(a.lastLoginAt);
  d.passwordChangedAt = isoTime(a.passwordChangedAt);
  return d;
}

/// With the effective rights, resolved against `roles` (all roles).
UserDto toDto(const UserAccount a, const(Role)[] roles) {
  import std.algorithm : map;
  import std.array : array;

  auto d = toDto(a);
  d.rights = effectiveRights(a.roles, roles).map!(x => x.key).array;
  return d;
}

RoleDto toDto(const Role r, long members) {
  import std.algorithm : map;
  import std.array : array;

  RoleDto d;
  d.name = r.name.value;
  d.label = r.label;
  d.description = r.description;
  d.rights = r.effectiveRights.map!(x => x.key).array;
  d.builtIn = r.builtIn;
  d.locked = r.isAdministrator;
  d.members = members;
  d.createdAt = isoTime(r.createdAt);
  d.modifiedAt = isoTime(r.modifiedAt);
  return d;
}

AccessRightDto toDto(const AccessRightInfo i) {
  return AccessRightDto(i.key, i.label, i.description, i.area);
}

/// With file count and bytes of the site.
SiteDto toDto(const Site s, long files, long bytes) {
  import std.algorithm : canFind;

  SiteDto d;
  d.key = s.key.value;
  d.name = s.name;
  d.hosts = s.hosts.dup;
  d.languages = s.languages.dup;
  d.defaultLanguage = s.defaultLanguage;
  d.isDefault = s.isDefault;
  foreach (c; s.content)
    if (s.languages.canFind(c.language))
      d.content ~= SiteContentDto(c.language, c.title, c.tagline, c.body);
  d.files = files;
  d.bytes = bytes;
  d.createdAt = isoTime(s.createdAt);
  d.modifiedAt = isoTime(s.modifiedAt);
  return d;
}

SiteContentDto toDto(const SiteContent c) {
  return SiteContentDto(c.language, c.title, c.tagline, c.body);
}

FileDto toDto(const StoredFile f) {
  FileDto d;
  d.id = f.id.value;
  d.site = f.site.value;
  d.name = f.name;
  d.contentType = f.contentType;
  d.kind = f.kind.to!string;
  d.size = f.size;
  d.sha256 = f.sha256;
  d.description = f.description;
  d.isPublic = f.isPublic;
  d.inline = f.inlineSafe;
  d.uploadedBy = f.uploadedBy;
  d.createdAt = isoTime(f.createdAt);
  d.modifiedAt = isoTime(f.modifiedAt);
  return d;
}

/// 1536 → "1.5 KB"
string byteSize(long bytes) pure {
  import std.format : format;

  if (bytes < 0)
    return "–";
  if (bytes < 1024)
    return format("%s B", bytes);
  immutable units = ["KB", "MB", "GB", "TB"];
  double v = bytes;
  size_t u;
  for (v /= 1024; v >= 1024 && u + 1 < units.length; v /= 1024)
    u++;
  return format(v < 10 ? "%.1f %s" : "%.0f %s", v, units[u]);
}

///
unittest {
  assert(byteSize(0) == "0 B" && byteSize(1536) == "1.5 KB" && byteSize(50 * 1024 * 1024) == "50 MB");
  assert(SiteContentDto("en", "", "", "One\r\n\r\n\n Two \n\n").paragraphs == ["One", "Two"]);
}

struct IpRuleDto {
  string id;
  string network;
  string action;
  string scope_;
  string note;
  string createdBy;
  string createdAt;
}

IpRuleDto toDto(const IpRule r) {
  return IpRuleDto(r.id.value, r.network.toString, r.action.to!string, r.scope_.to!string, r.note, r.createdBy,
    isoTime(r.createdAt));
}

/// One service plan at one node of the hierarchy.
struct EntitlementRowDto {
  string plan;
  string service;
  string unit;
  /// `unlimited` (-1) = pay per use.
  long quota;
  /// Taken by the consumers below (directories with entitlements, subaccounts).
  long assignedBelow;
  /// A consumer below takes it without limit.
  bool unlimitedBelow;
  /// quota − assignedBelow; -1 if unlimited.
  long available;
  /// Subaccounts: used this month in billing units; -1 = not measured.
  double used = -1;
  bool overQuota;
}

/// A role collection that applies to a node from above.
struct InheritedRoleCollectionDto {
  /// "global" | "directory:<key>"
  string origin;
  RoleCollection collection;
}

/// A node of the hierarchy with everything the detail view shows.
struct NodeDto {
  /// "global" | "directory" | "subaccount"
  string kind;
  /// "global", "directory:<key>", "subaccount:<key>"
  string node;
  string key;
  string name;
  string description;
  // global account
  string subdomainPrefix;
  string subdomainPattern;
  string contract;
  string currency;
  string[] admins;
  // directories
  string parent;
  bool manageEntitlements;
  bool manageAuthorizations;
  string owner;
  size_t depth;
  // subaccounts
  string directory;
  string region;
  string regionLabel;
  string subdomain;
  string purpose;
  string stage;
  string domain;
  string[] sites;
  bool betaFeatures;
  /// Subaccounts: the user group and the selected services ("" = every
  /// service); `admins` holds the subaccount administrators.
  string[] members;
  string[] services;
  /// Subaccounts: tenants with their spaces.
  Tenant[] tenants;
  /// Own cost center ("" = inherited) and the one that applies.
  string costCenter;
  string effectiveCostCenter;
  /// Where it draws entitlements from ("global", "directory:<key>"); "" for the global account.
  string entitlementSource;
  EntitlementRowDto[] entitlements;
  RoleCollection[] roleCollections;
  InheritedRoleCollectionDto[] inherited;
  /// Node ids of the direct children.
  string[] children;
  LandscapeIssue[] issues;
  Advice[] advice;
  /// Costs of the subtree in the month.
  double monthCost = 0;
  string createdAt;
  string modifiedAt;
}

/// A line of the hierarchy tree.
struct TreeItemDto {
  string node;
  string kind;
  string key;
  string name;
  /// 0 = global account
  int level;
  string stage;
  string region;
  string domain;
  string subdomain;
  bool manageEntitlements;
  bool manageAuthorizations;
  size_t errors;
  size_t warnings;
  size_t advice;
  /// Subaccounts in the subtree (directories).
  size_t subaccounts;
  size_t sites;
  size_t tenants;
  double monthCost = 0;
}

struct LandscapeDto {
  string month;
  string currency;
  TreeItemDto[] tree;
  ServicePlan[] plans;
  LandscapeIssue[] issues;
  Advice[] advice;
  double monthCost = 0;
  long subaccounts;
  long directories;
}

/// A row of the bill: a node with its total; subaccounts with their lines.
struct BillRowDto {
  string node;
  string kind;
  string key;
  string name;
  int level;
  string costCenter;
  double total = 0;
  ChargeLine[] lines;
  long requests;
  long bytesOut;
  long storageBytes;
  long sites;
}

struct BillDto {
  string month;
  string currency;
  double total = 0;
  BillRowDto[] rows;
  double[string] byPlan;
  UsageRecord[] unassigned;
  /// Months with usage, newest first.
  string[] months;
  ServicePlan[] plans;
}
