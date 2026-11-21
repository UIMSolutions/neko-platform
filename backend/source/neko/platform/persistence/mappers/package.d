/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Converters between stored records and domain entities.
module neko.platform.persistence.mappers;

import std.algorithm : canFind, map, sort, uniq;
import std.array : array;
import std.conv : to;
import std.datetime.systime : SysTime;
import neko.platform.domain;
import neko.platform.persistence.records;

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

UserRecord toRecord(const UserAccount a) {
  return UserRecord(a.id.value, a.userName.value, a.displayName, a.email, a.roles.dup,
    a.roles.length > 0 ? a.roles[0] : "", a.active,
    a.passwordHash, timeToText(a.createdAt), timeToText(a.modifiedAt), timeToText(a.lastLoginAt),
    timeToText(a.passwordChangedAt), a.sites.dup);
}

UserAccount toEntity(const UserRecord r) {
  UserAccount a;
  a.id = AccountId(r.id);
  a.userName = UserName(r.userName);
  a.displayName = r.displayName;
  a.email = r.email;
  // Older documents: the single role "viewer" | "admin" is the built-in role
  // of the same name. Unknown names are kept; they grant nothing.
  RoleName[] names;
  foreach (n; r.roles.length > 0 ? r.roles : (r.role.length > 0 ? [r.role] : [viewerRole]))
    try
      names ~= RoleName(n);
    catch (ValidationException) {
    }
  a.roles = names.length > 0 ? names.map!(n => n.value).array.sort.uniq.array : [viewerRole];
  a.active = r.active;
  a.passwordHash = r.passwordHash;
  a.createdAt = textToTime(r.createdAt);
  a.modifiedAt = textToTime(r.modifiedAt);
  a.lastLoginAt = textToTime(r.lastLoginAt);
  a.passwordChangedAt = textToTime(r.passwordChangedAt);
  a.sites = r.sites.dup;
  return a;
}

RoleRecord toRecord(const Role r) {
  return RoleRecord(r.name.value, r.label, r.description, r.rights.map!(x => x.key).array, r.builtIn,
    timeToText(r.createdAt), timeToText(r.modifiedAt), r.knownRights.map!(x => x.key).array);
}

Role toEntity(const RoleRecord r) {
  Role role;
  role.name = RoleName(r.name);
  role.label = r.label.length > 0 ? r.label : r.name;
  role.description = r.description;
  // Rights of a newer version that this binary does not know are dropped.
  foreach (k; r.rights) {
    AccessRight right;
    if (tryParseAccessRight(k, right))
      role.rights ~= right;
  }
  role.rights = role.rights.sort.uniq.array;
  role.knownRights = r.knownRights.length > 0 ? parseKnown(r.knownRights) : firstAccessRights.dup;
  role.builtIn = r.builtIn;
  role.createdAt = textToTime(r.createdAt);
  role.modifiedAt = textToTime(r.modifiedAt);
  return role;
}

SiteRecord toRecord(const Site s) {
  SiteContentRecord[] content;
  foreach (c; s.content)
    content ~= SiteContentRecord(c.language, c.title, c.tagline, c.body);
  return SiteRecord(s.key.value, s.name, s.hosts.dup, s.languages.dup, content, s.isDefault,
    timeToText(s.createdAt), timeToText(s.modifiedAt));
}

Site toEntity(const SiteRecord r) {
  Site s;
  s.key = SiteKey(r.key);
  s.name = r.name.length ? r.name : r.key;
  s.hosts = r.hosts.dup;
  // Invalid tags (edited by hand) are dropped; a site always has a language.
  foreach (l; r.languages)
    try {
      auto tag = LanguageTag(l).value;
      if (!s.languages.canFind(tag))
        s.languages ~= tag;
    } catch (ValidationException) {
    }
  if (s.languages.length == 0)
    s.languages = ["en"];
  foreach (c; r.content)
    try
      s.content ~= SiteContent(LanguageTag(c.language).value, c.title, c.tagline, c.body);
    catch (ValidationException) {
    }
  s.isDefault = r.isDefault;
  s.createdAt = textToTime(r.createdAt);
  s.modifiedAt = textToTime(r.modifiedAt);
  return s;
}

FileRecord toRecord(const StoredFile f) {
  return FileRecord(f.id.value, f.site.value, f.name, f.size, f.sha256, f.description, f.isPublic, f.uploadedBy,
    timeToText(f.createdAt), timeToText(f.modifiedAt), f.contentType);
}

StoredFile toEntity(const FileRecord r) {
  StoredFile f;
  f.id = FileId(r.id);
  f.site = SiteKey(r.site);
  f.name = r.name;
  f.contentType = contentTypeFor(r.name);
  f.kind = kindOf(f.contentType);
  f.size = r.size;
  f.sha256 = r.sha256;
  f.description = r.description;
  f.isPublic = r.isPublic;
  f.uploadedBy = r.uploadedBy;
  f.createdAt = textToTime(r.createdAt);
  f.modifiedAt = textToTime(r.modifiedAt);
  return f;
}

IpRuleRecord toRecord(const IpRule r) {
  return IpRuleRecord(r.id.value, r.network.toString, r.action.to!string, r.scope_.to!string, r.note, r.createdBy,
    timeToText(r.createdAt));
}

/// Throws for unreadable networks (a hand-edited file): better to fail at start
/// than to silently drop a deny rule.
IpRule toEntity(const IpRuleRecord r) {
  IpRule rule;
  rule.id = IpRuleId(r.id);
  rule.network = IpNetwork(r.network);
  rule.action = toEnum(r.action, IpAction.deny);
  rule.scope_ = toEnum(r.scope_, NetworkScope.all);
  rule.note = r.note;
  rule.createdBy = r.createdBy;
  rule.createdAt = textToTime(r.createdAt);
  return rule;
}

private EntitlementRecord[] toRecords(const(Entitlement)[] list) {
  return list.map!(e => EntitlementRecord(e.plan, e.quota)).array;
}

private Entitlement[] toEntitlements(const(EntitlementRecord)[] list) {
  return list.map!(e => Entitlement(e.plan, e.quota)).array;
}

private RoleCollectionRecord[] toRecords(const(RoleCollection)[] list) {
  return list.map!(r => RoleCollectionRecord(r.name, r.description, r.rights.dup, r.members.dup)).array;
}

private RoleCollection[] toCollections(const(RoleCollectionRecord)[] list) {
  return list.map!(r => RoleCollection(r.name, r.description, r.rights.dup, r.members.dup)).array;
}

GlobalAccountRecord toRecord(const GlobalAccount g) {
  return GlobalAccountRecord(g.name, g.subdomainPrefix, g.subdomainPattern, g.contract, g.currency, g.costCenter,
    g.admins.dup, toRecords(g.entitlements), toRecords(g.roleCollections), timeToText(g.modifiedAt));
}

GlobalAccount toEntity(const GlobalAccountRecord r) {
  GlobalAccount g;
  g.name = r.name;
  if (r.subdomainPrefix.length)
    g.subdomainPrefix = r.subdomainPrefix;
  if (r.subdomainPattern.length)
    g.subdomainPattern = r.subdomainPattern;
  if (r.contract.length)
    g.contract = r.contract;
  if (r.currency.length)
    g.currency = r.currency;
  g.costCenter = r.costCenter;
  g.admins = r.admins.dup;
  g.entitlements = toEntitlements(r.entitlements);
  g.roleCollections = toCollections(r.roleCollections);
  g.modifiedAt = textToTime(r.modifiedAt);
  return g;
}

DirectoryRecord toRecord(const Directory d) {
  return DirectoryRecord(d.key, d.name, d.description, d.parent, d.manageEntitlements, d.manageAuthorizations,
    d.costCenter, d.owner, toRecords(d.entitlements), toRecords(d.roleCollections), timeToText(d.createdAt),
    timeToText(d.modifiedAt));
}

Directory toEntity(const DirectoryRecord r) {
  return Directory(r.key, r.name, r.description, r.parent, r.manageEntitlements, r.manageAuthorizations, r.costCenter,
    r.owner, toEntitlements(r.entitlements), toCollections(r.roleCollections), textToTime(r.createdAt),
    textToTime(r.modifiedAt));
}

SubaccountRecord toRecord(const Subaccount s) {
  return SubaccountRecord(s.key, s.name, s.description, s.directory, s.region, s.subdomain, s.purpose,
    s.stage.to!string, s.domain.label, s.sites.dup, s.costCenter, s.betaFeatures, toRecords(s.entitlements),
    toRecords(s.roleCollections), timeToText(s.createdAt), timeToText(s.modifiedAt));
}

Subaccount toEntity(const SubaccountRecord r) {
  return Subaccount(r.key, r.name, r.description, r.directory, r.region, r.subdomain, r.purpose,
    toEnum(r.stage, Stage.dev), toDomain(r.domain), r.sites.dup, r.costCenter, r.betaFeatures,
    toEntitlements(r.entitlements), toCollections(r.roleCollections), textToTime(r.createdAt), textToTime(r.modifiedAt));
}

ServicePlanRecord toRecord(const ServicePlan p) {
  return ServicePlanRecord(p.key, p.service, p.plan, p.description, p.unit, p.unitSize, p.price, p.meter.to!string);
}

ServicePlan toEntity(const ServicePlanRecord r) {
  return ServicePlan(r.key, r.service, r.plan, r.description, r.unit, r.unitSize > 0 ? r.unitSize : 1, r.price,
    toEnum(r.meter, Meter.none));
}

UsageDocument toRecord(const UsageRecord u) {
  return UsageDocument(u.month, u.site, u.requests, u.bytesOut, u.peakStorageBytes);
}

UsageRecord toEntity(const UsageDocument d) {
  return UsageRecord(d.month, d.site, d.requests, d.bytesOut, d.peakStorageBytes);
}

private AccessRight[] parseKnown(const(string)[] keys) {
  AccessRight[] result;
  foreach (k; keys) {
    AccessRight right;
    if (tryParseAccessRight(k, right))
      result ~= right;
  }
  return result.sort.uniq.array;
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

///
unittest {
  // a user document written before roles existed
  UserRecord old;
  old.id = "1";
  old.userName = "jane";
  old.role = "admin";
  auto jane = toEntity(old);
  assert(jane.roles == [adminRole] && jane.isAdmin);
  auto back = toRecord(jane);
  assert(back.roles == [adminRole] && back.role == adminRole);

  RoleRecord rec;
  rec.name = "ops";
  rec.rights = ["users.read", "status.read", "future.right", "status.read"];
  auto ops = toEntity(rec);
  assert(ops.label == "ops" && ops.rights == [AccessRight.statusRead, AccessRight.usersRead]);
  assert(toRecord(ops).rights == ["status.read", "users.read"]);
}

///
unittest {
  SiteRecord rec;
  rec.key = "shop";
  rec.languages = ["DE", "bad tag!", "en", "de"];
  rec.content = [SiteContentRecord("de", "Willkommen"), SiteContentRecord("x_y", "lost")];
  auto site = toEntity(rec);
  assert(site.name == "shop" && site.languages == ["de", "en"] && site.content.length == 1);
  assert(toRecord(site).languages == ["de", "en"]);

  FileRecord f;
  f.id = "1";
  f.site = "shop";
  f.name = "intro.mp4";
  f.contentType = "text/html"; // never trusted
  auto file = toEntity(f);
  assert(file.contentType == "video/mp4" && file.kind == FileKind.video);
}
