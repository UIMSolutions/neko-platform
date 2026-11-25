/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The account hierarchy, modelled on NEKO BTP:
///
///   Global Account   governance: contract, cost center, the purchased
///                    entitlements (service plans and quotas), global role
///                    collections, the subdomain scheme
///   Directories      group subaccounts (nested up to `maxDirectoryDepth`);
///                    optionally manage their own entitlements (a budget that
///                    their subaccounts draw from) and role collections
///   Subaccounts      where things run: region, subdomain, purpose, stage,
///                    security domain; logically separate, with their own
///                    administrators, user group and selected services (whose
///                    access rights their role collections may grant)
///   Tenants          one or more per subaccount (exactly one is the default
///                    tenant), logically separated from each other
///   Spaces           one or more per tenant, separated within the tenant;
///                    every tenant has the space "default"
///
/// Every subaccount can have a disaster recovery plan: a secondary region it
/// fails over to (see domain.entities.recovery).
///
/// Global accounts themselves are physically separate: each has its own
/// data directory (see domain.entities.globalaccounts); this module models the
/// inside of one global account.
///
/// A service call runs in one tenant and one space (`Landscape.resolveCall`):
/// the tenant from the headers or the host name, the space from the headers,
/// else the default space.
///
/// Entitlements flow down: a subaccount draws from the nearest directory
/// above it that manages entitlements, else from the global account; such a
/// directory itself draws from the next level up. `validate` reports
/// over-assignment and broken rules; `advise` recommends where directory
/// entitlements and role collections help — and where they do not.
module neko.platform.domain.entities.landscape;

import std.algorithm : any, all, canFind, count, countUntil, filter, map, sort, sum, uniq;
import std.array : array, join, replace;
import std.ascii : isDigit, isLower;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.string : split, strip, toLower;
import neko.platform.domain.enumerations.rights : accessRights;
import neko.platform.domain.enumerations.security : SecurityDomain;
import neko.platform.domain.exceptions;
import neko.platform.domain.entities.recovery : RecoveryPlan, activeRegion, recoveryAdvice, recoveryIssues;

@safe:

enum maxDirectoryDepth = 5;
/// Key of the space every tenant has; calls without a space run there.
enum defaultSpaceKey = "default";
/// Key of the tenant a new subaccount starts with.
enum defaultTenantKey = "default";
/// Quota of a pay-per-use entitlement: no fixed amount.
enum long unlimited = -1;

/// The life-cycle stage of a subaccount.
enum Stage {
  sandbox,
  dev,
  test,
  qa,
  prod,
}

bool isProduction(Stage s) pure nothrow {
  return s == Stage.prod;
}

/// A region a subaccount can live in.
struct RegionInfo {
  string id;
  string provider;
  string location;
  /// Operated under EU Access (data and support stay in the EU).
  bool euAccess;
}

immutable RegionInfo[] regions = [
  RegionInfo("eu10", "AWS", "Europe (Frankfurt)"),
  RegionInfo("eu11", "AWS", "Europe (Frankfurt) – EU Access", true),
  RegionInfo("eu20", "Azure", "Europe (Netherlands)"),
  RegionInfo("eu30", "Google Cloud", "Europe (Frankfurt)"),
  RegionInfo("ch20", "Azure", "Switzerland (Zurich)"),
  RegionInfo("us10", "AWS", "US East (VA)"),
  RegionInfo("us20", "Azure", "US West (WA)"),
  RegionInfo("us30", "Google Cloud", "US Central (IA)"),
  RegionInfo("ca10", "AWS", "Canada (Montreal)"),
  RegionInfo("br10", "AWS", "Brazil (São Paulo)"),
  RegionInfo("jp10", "AWS", "Japan (Tokyo)"),
  RegionInfo("ap10", "AWS", "Australia (Sydney)"),
  RegionInfo("ap21", "Azure", "Singapore"),
  RegionInfo("in30", "Google Cloud", "India (Mumbai)"),
  RegionInfo("onprem", "Self-hosted", "Own data center"),
];

bool tryRegion(string id, out RegionInfo info) pure nothrow {
  foreach (r; regions)
    if (r.id == id) {
      info = r;
      return true;
    }
  return false;
}

/// A service plan with a quota at one level.
struct Entitlement {
  /// ServicePlan.key ("files.storage").
  string plan;
  /// Units; `unlimited` = pay per use.
  long quota;
}

/// A named set of access rights with its members, valid at one level (and,
/// for the global account and directories, for everything below).
struct RoleCollection {
  string name;
  string description;
  /// Access right keys ("files.manage").
  string[] rights;
  /// User names.
  string[] members;

  RoleCollection copy() const pure nothrow {
    return RoleCollection(name, description, rights.dup, members.dup);
  }
}

private RoleCollection[] copyAll(const(RoleCollection)[] list) pure nothrow {
  RoleCollection[] r;
  foreach (x; list)
    r ~= x.copy;
  return r;
}

struct GlobalAccount {
  string name = "Global Account";
  /// First part of every subdomain ({global}).
  string subdomainPrefix = "neko";
  /// Placeholders: {global}, {directory}, {purpose}, {stage}, {region}.
  string subdomainPattern = "{global}-{purpose}-{stage}";
  /// "CPEA" (consumption credits), "PAYG" (pay as you go) or "subscription".
  string contract = "CPEA";
  string currency = "EUR";
  string costCenter;
  /// Governance contacts.
  string[] admins;
  Entitlement[] entitlements;
  RoleCollection[] roleCollections;
  SysTime modifiedAt;

  GlobalAccount copy() const pure nothrow {
    return GlobalAccount(name, subdomainPrefix, subdomainPattern, contract, currency, costCenter, admins.dup,
      entitlements.dup, copyAll(roleCollections), modifiedAt);
  }
}

struct Directory {
  string key;
  string name;
  string description;
  /// Key of the parent directory; "" = directly below the global account.
  string parent;
  /// Holds its own entitlements, which the subaccounts below draw from.
  bool manageEntitlements;
  /// Holds role collections that apply to every subaccount below.
  bool manageAuthorizations;
  string costCenter;
  string owner;
  Entitlement[] entitlements;
  RoleCollection[] roleCollections;
  SysTime createdAt;
  SysTime modifiedAt;

  Directory copy() const pure nothrow {
    return Directory(key, name, description, parent, manageEntitlements, manageAuthorizations, costCenter, owner,
      entitlements.dup, copyAll(roleCollections), createdAt, modifiedAt);
  }
}

/// A data space of a tenant. Spaces are separated from each other within
/// their tenant; the space `defaultSpaceKey` always exists.
struct Space {
  string key;
  string name;
  string description;
  SysTime createdAt;

  bool isDefault() const pure nothrow {
    return key == defaultSpaceKey;
  }

  Space copy() const pure nothrow {
    return Space(key, name, description, createdAt);
  }
}

/// A tenant of a subaccount: logically separated from the other tenants,
/// with one or more spaces.
struct Tenant {
  string key;
  string name;
  string description;
  /// Calls that name no tenant run in the default tenant of the subaccount.
  bool isDefault;
  Space[] spaces;
  SysTime createdAt;
  SysTime modifiedAt;

  Tenant copy() const pure nothrow {
    Space[] list;
    foreach (sp; spaces)
      list ~= sp.copy;
    return Tenant(key, name, description, isDefault, list, createdAt, modifiedAt);
  }

  bool trySpace(string key, out Space space) const pure nothrow {
    foreach (sp; spaces)
      if (sp.key == key) {
        space = sp.copy;
        return true;
      }
    return false;
  }

  /// Adds the default space if it is missing (first, as the tenant's home).
  void ensureDefaultSpace(SysTime now) pure nothrow {
    foreach (sp; spaces)
      if (sp.isDefault)
        return;
    spaces = Space(defaultSpaceKey, "Default", "", now) ~ spaces;
  }
}

struct Subaccount {
  string key;
  string name;
  string description;
  /// Key of the directory; "" = directly below the global account.
  string directory;
  string region = "eu10";
  string subdomain;
  /// What it is for ("shop", "integration", …): part of the subdomain.
  string purpose;
  Stage stage = Stage.dev;
  SecurityDomain domain;
  /// "" = inherited from the directory / global account.
  string costCenter;
  bool betaFeatures;
  Entitlement[] entitlements;
  RoleCollection[] roleCollections;
  SysTime createdAt;
  SysTime modifiedAt;
  /// Subaccount administrators (user names): manage its tenants, spaces,
  /// user group, services and role collections.
  string[] admins;
  /// The user group of the subaccount (user names): the people its role
  /// collections can be given to (besides its administrators).
  string[] members;
  /// Keys of the services selected for the subaccount (`serviceCatalogue`):
  /// its role collections can only grant their access rights. Empty = every
  /// service.
  string[] services;
  /// One or more, exactly one of them the default tenant.
  Tenant[] tenants;
  /// Multi-region disaster recovery (disabled = unprotected).
  RecoveryPlan recovery;

  Subaccount copy() const pure nothrow {
    Tenant[] list;
    foreach (t; tenants)
      list ~= t.copy;
    return Subaccount(key, name, description, directory, region, subdomain, purpose, stage, domain, costCenter,
      betaFeatures, entitlements.dup, copyAll(roleCollections), createdAt, modifiedAt, admins.dup, members.dup,
      services.dup, list, recovery.copy);
  }

  bool tryTenant(string key, out Tenant tenant) const pure nothrow {
    foreach (t; tenants)
      if (t.key == key) {
        tenant = t.copy;
        return true;
      }
    return false;
  }

  /// The default tenant (the first one if none is marked).
  bool tryDefaultTenant(out Tenant tenant) const pure nothrow {
    foreach (t; tenants)
      if (t.isDefault) {
        tenant = t.copy;
        return true;
      }
    if (tenants.length == 0)
      return false;
    tenant = tenants[0].copy;
    return true;
  }

  bool isAdmin(string user) const pure nothrow {
    return admins.canFind(user);
  }

  /// Administrators and members.
  bool isUser(string user) const pure nothrow {
    return admins.canFind(user) || members.canFind(user);
  }

  /// Whether the role collections of the subaccount may grant rights of `service`.
  bool allowsService(string service) const pure nothrow {
    return services.length == 0 || services.canFind(service);
  }

  /// A default tenant with its default space, if there is none; the default
  /// space in every tenant; exactly one default tenant.
  void ensureTenancy(SysTime now) pure nothrow {
    if (tenants.length == 0)
      tenants = [Tenant(defaultTenantKey, "Default", "", true, null, now, now)];
    foreach (ref t; tenants)
      t.ensureDefaultSpace(now);
    if (!tenants.any!(t => t.isDefault))
      tenants[0].isDefault = true;
  }
}

/// A service whose access rights a subaccount can select (the area of the
/// rights: "files" for files.read and files.manage).
struct ServiceInfo {
  string key;
  string label;
  /// Access right keys.
  string[] rights;
}

/// The services of the platform, derived from the access right catalogue.
ServiceInfo[] serviceCatalogue() pure {
  ServiceInfo[] list;
  foreach (r; accessRights) {
    auto service = serviceOfRight(r.key);
    auto i = list.countUntil!(x => x.key == service);
    if (i < 0)
      list ~= ServiceInfo(service, r.area == service.capitalizedWord ? r.area : r.area ~ " · " ~ service, [r.key]);
    else
      list[i].rights ~= r.key;
  }
  return list;
}

/// "files.manage" → "files"
string serviceOfRight(string right) pure nothrow {
  foreach (i, c; right)
    if (c == '.')
      return right[0 .. i];
  return right;
}

private string capitalizedWord(string s) pure {
  import std.ascii : toUpper;

  return s.length ? toUpper(s[0]) ~ s[1 .. $] : s;
}

/// Where a service call runs.
struct CallContext {
  /// Key of the global account (set by the caller: global accounts are physically separate).
  string globalAccount;
  string subaccount;
  string subdomain;
  string tenant;
  string space;
  /// The region the subaccount runs in now: its primary region, or the
  /// secondary one after a disaster recovery failover.
  string region;
  /// How the tenant was found: "header", "subdomain" or "default".
  string source;
}

/// What a request says about its tenant and space.
struct CallRequest {
  /// Host name of the request (lower case, without port).
  string host;
  /// X-Neko-Subaccount: key or subdomain.
  string subaccount;
  /// X-Neko-Tenant
  string tenant;
  /// X-Neko-Space
  string space;
}

/// What a unit of a service plan is measured with.
enum Meter {
  /// Not measured: billed by the entitled quota (a fixed monthly fee per unit).
  none,
  /// Requests that run in the subaccount (service calls, public files).
  requests,
  /// Bytes sent for those requests.
  egressBytes,
  /// Peak bytes of the files of the subaccount in the month.
  storageBytes,
}

struct ServicePlan {
  /// "files.storage"
  string key;
  string service;
  string plan;
  string description;
  /// Name of the billing unit ("GB-month", "1,000 requests").
  string unit;
  /// Measured amount per billing unit (1 GiB = 1073741824 bytes, 1000 requests).
  double unitSize = 1;
  /// Price per billing unit and month (currency of the global account).
  double price = 0;
  Meter meter;
}

/// The plans every instance starts with: what the platform measures, plus a
/// fixed-fee plan as an example of entitlement-based billing.
ServicePlan[] defaultPlans() pure {
  enum gib = 1024.0 * 1024 * 1024;
  return [
    ServicePlan("platform.requests", "Platform", "requests", "Requests that run in a subaccount",
      "1,000 requests", 1000, 0.04, Meter.requests),
    ServicePlan("network.egress", "Network", "egress", "Data sent for the requests of a subaccount", "GB", gib, 0.09,
      Meter.egressBytes),
    ServicePlan("files.storage", "Files", "standard", "Peak size of the subaccount's files in the month", "GB-month",
      gib, 0.025, Meter.storageBytes),
    ServicePlan("support.premium", "Support", "premium", "Premium support, per entitled unit", "unit-month", 1, 150,
      Meter.none),
  ];
}

/// "dev" → Stage.dev
Stage parseStage(string text) pure {
  switch (text.strip.toLower) {
  case "sandbox":
    return Stage.sandbox;
  case "dev", "development":
    return Stage.dev;
  case "test":
    return Stage.test;
  case "qa", "quality":
    return Stage.qa;
  case "prod", "production", "live":
    return Stage.prod;
  default:
    throw new ValidationException("Stage must be sandbox, dev, test, qa or prod, not '" ~ text ~ "'");
  }
}

/// Keys of directories, subaccounts and plans: 2–40 characters a-z, 0-9,
/// '-' and '.', starting with a letter.
string landscapeKey(string text, string what) pure {
  auto k = text.strip.toLower;
  if (k.length < 2 || k.length > 40 || !k[0].isLower || !k.all!(c => c.isLower || c.isDigit || c == '-' || c == '.'))
    throw new ValidationException(what ~ " key '" ~ text.strip ~ "' must have 2 to 40 characters a-z, 0-9, '-' or '.', "
        ~ "starting with a letter");
  return k;
}

/// A DNS label: 1–63 characters a-z, 0-9, '-', not starting or ending with '-'.
string subdomainLabel(string text) pure {
  auto s = text.strip.toLower;
  if (s.length == 0 || s.length > 63 || s[0] == '-' || s[$ - 1] == '-'
      || !s.all!(c => c.isLower || c.isDigit || c == '-'))
    throw new ValidationException("Subdomain '" ~ text.strip ~ "' must have 1 to 63 characters a-z, 0-9 and '-', "
        ~ "not starting or ending with '-'");
  return s;
}

/// The subdomain the scheme gives a subaccount.
string subdomainFor(const GlobalAccount g, const Subaccount s, string directoryKey) pure {
  auto text = g.subdomainPattern.toLower.replace("{global}", g.subdomainPrefix).replace("{directory}", directoryKey)
    .replace("{purpose}", s.purpose.length ? s.purpose : s.key).replace("{stage}", s.stage.to!string)
    .replace("{region}", s.region).replace(".", "-");
  // collapse "--" left by empty parts
  while (text.canFind("--"))
    text = text.replace("--", "-");
  while (text.length && text[0] == '-')
    text = text[1 .. $];
  while (text.length && text[$ - 1] == '-')
    text = text[0 .. $ - 1];
  return text.length > 63 ? text[0 .. 63] : text;
}

/// Something wrong in the landscape.
struct LandscapeIssue {
  /// "error" | "warning"
  string severity;
  /// "global", "directory:<key>", "subaccount:<key>"
  string node;
  string message;
}

/// A recommendation.
struct Advice {
  string node;
  /// "entitlements" | "authorizations" | "structure" | "security" | "recovery"
  string topic;
  string recommendation;
  string reason;
}

/// The whole hierarchy, for rules that need more than one node.
struct Landscape {
  GlobalAccount global;
  Directory[] directories;
  Subaccount[] subaccounts;
  ServicePlan[] plans;

  bool tryDirectory(string key, out Directory d) const pure nothrow {
    foreach (x; directories)
      if (x.key == key) {
        d = x.copy;
        return true;
      }
    return false;
  }

  bool trySubaccount(string key, out Subaccount s) const pure nothrow {
    foreach (x; subaccounts)
      if (x.key == key) {
        s = x.copy;
        return true;
      }
    return false;
  }

  bool tryPlan(string key, out ServicePlan p) const pure nothrow {
    foreach (x; plans)
      if (x.key == key) {
        p = x;
        return true;
      }
    return false;
  }

  /// The directory and its ancestors, nearest first. Stops at cycles.
  Directory[] ancestors(string directoryKey) const pure nothrow {
    Directory[] chain;
    auto key = directoryKey;
    while (key.length) {
      Directory d;
      if (!tryDirectory(key, d) || chain.any!(c => c.key == key) || chain.length > maxDirectoryDepth + 1)
        break;
      chain ~= d;
      key = d.parent;
    }
    return chain;
  }

  /// Levels of directories down to and including this one (1 = top level).
  size_t depth(string directoryKey) const pure nothrow {
    return ancestors(directoryKey).length;
  }

  /// Where a node draws its entitlements from: "global" or "directory:<key>".
  /// `startDirectory` = the directory containing the node.
  string entitlementSource(string startDirectory) const pure nothrow {
    foreach (d; ancestors(startDirectory))
      if (d.manageEntitlements)
        return "directory:" ~ d.key;
    return "global";
  }

  /// Source of a subaccount.
  string sourceOf(const Subaccount s) const pure nothrow {
    return entitlementSource(s.directory);
  }

  /// Source of a directory that manages entitlements (its parent chain).
  string sourceOf(const Directory d) const pure nothrow {
    return entitlementSource(d.parent);
  }

  /// The entitlements held by a source node.
  const(Entitlement)[] entitlementsOf(string node) const pure nothrow {
    if (node == "global")
      return global.entitlements;
    foreach (d; directories)
      if ("directory:" ~ d.key == node)
        return d.entitlements;
    foreach (s; subaccounts)
      if ("subaccount:" ~ s.key == node)
        return s.entitlements;
    return null;
  }

  /// Quota of `plan` at `node`; 0 if it has none.
  long quotaOf(string node, string plan) const pure nothrow {
    foreach (e; entitlementsOf(node))
      if (e.plan == plan)
        return e.quota;
    return 0;
  }

  /// Whether `node` holds `plan` at all.
  bool holds(string node, string plan) const pure nothrow {
    return entitlementsOf(node).any!(e => e.plan == plan);
  }

  /// Sum of the quotas the direct consumers of `source` took of `plan`
  /// (unlimited consumers are not counted). `unlimitedConsumers` tells
  /// whether one of them is pay-per-use.
  long assignedFrom(string source, string plan, out bool unlimitedConsumers) const pure nothrow {
    long n;
    foreach (d; directories)
      if (d.manageEntitlements && sourceOf(d) == source)
        foreach (e; d.entitlements)
          if (e.plan == plan) {
            if (e.quota == unlimited)
              unlimitedConsumers = true;
            else
              n += e.quota;
          }
    foreach (s; subaccounts)
      if (sourceOf(s) == source)
        foreach (e; s.entitlements)
          if (e.plan == plan) {
            if (e.quota == unlimited)
              unlimitedConsumers = true;
            else
              n += e.quota;
          }
    return n;
  }

  /// Subaccounts in the subtree of a directory.
  Subaccount[] subaccountsBelow(string directoryKey) const pure nothrow {
    Subaccount[] result;
    foreach (s; subaccounts)
      if (ancestors(s.directory).any!(a => a.key == directoryKey))
        result ~= s.copy;
    return result;
  }

  /// The cost center that applies to a subaccount.
  string costCenterOf(const Subaccount s) const pure nothrow {
    if (s.costCenter.length)
      return s.costCenter;
    foreach (d; ancestors(s.directory))
      if (d.costCenter.length)
        return d.costCenter;
    return global.costCenter;
  }

  /// Rule violations.
  LandscapeIssue[] validate() const pure {
    LandscapeIssue[] issues;
    void error(string node, string message) {
      issues ~= LandscapeIssue("error", node, message);
    }

    void warning(string node, string message) {
      issues ~= LandscapeIssue("warning", node, message);
    }

    // structure
    foreach (d; directories) {
      auto node = "directory:" ~ d.key;
      Directory parent;
      if (d.parent.length && !tryDirectory(d.parent, parent))
        error(node, "The parent directory '" ~ d.parent ~ "' does not exist");
      auto chain = ancestors(d.key);
      if (chain.length > maxDirectoryDepth)
        error(node, "Directories can be nested " ~ maxDirectoryDepth.to!string ~ " levels deep at most");
      if (!d.manageEntitlements && d.entitlements.length)
        warning(node, "Has entitlements but does not manage entitlements; they are ignored");
      if (!d.manageAuthorizations && d.roleCollections.length)
        warning(node, "Has role collections but does not manage authorizations; they are ignored");
    }
    string[] subdomains;
    foreach (s; subaccounts) {
      auto node = "subaccount:" ~ s.key;
      Directory dir;
      if (s.directory.length && !tryDirectory(s.directory, dir))
        error(node, "The directory '" ~ s.directory ~ "' does not exist");
      RegionInfo region;
      if (!tryRegion(s.region, region))
        error(node, "Unknown region '" ~ s.region ~ "'");
      if (subdomains.canFind(s.subdomain))
        error(node, "The subdomain '" ~ s.subdomain ~ "' is used twice; subdomains are unique in the region");
      subdomains ~= s.subdomain;

      // tenants and spaces
      if (s.tenants.length == 0)
        error(node, "Has no tenant; every subaccount needs at least one");
      else if (s.tenants.count!(t => t.isDefault) != 1)
        error(node, "Needs exactly one default tenant, has " ~ s.tenants.count!(t => t.isDefault).to!string);
      string[] tenantKeys;
      foreach (t; s.tenants) {
        if (tenantKeys.canFind(t.key))
          error(node, "The tenant key '" ~ t.key ~ "' is used twice");
        tenantKeys ~= t.key;
        if (!t.spaces.any!(sp => sp.isDefault))
          error(node, "The tenant " ~ t.key ~ " has no space '" ~ defaultSpaceKey ~ "'");
        string[] spaceKeys;
        foreach (sp; t.spaces) {
          if (spaceKeys.canFind(sp.key))
            error(node, "The space key '" ~ sp.key ~ "' is used twice in tenant " ~ t.key);
          spaceKeys ~= sp.key;
        }
      }

      // user group and services: what role collections may grant, and to whom
      foreach (svc; s.services)
        if (!serviceCatalogue().any!(x => x.key == svc))
          error(node, "Unknown service '" ~ svc ~ "'");
      foreach (rc; s.roleCollections) {
        foreach (m; rc.members)
          if (!s.isUser(m))
            error(node, "The role collection '" ~ rc.name ~ "' names " ~ m
                ~ ", who is not in the user group of the subaccount");
        foreach (r; rc.rights)
          if (!s.allowsService(serviceOfRight(r)))
            error(node, "The role collection '" ~ rc.name ~ "' grants " ~ r ~ ", but the service "
                ~ serviceOfRight(r) ~ " is not assigned to the subaccount");
      }

      // disaster recovery
      foreach (i; recoveryIssues(s))
        issues ~= LandscapeIssue(i.error ? "error" : "warning", node, "Disaster recovery: " ~ i.message);
    }
    if (global.admins.length == 0)
      warning("global", "No global account administrator is named");

    // entitlements
    void checkPlans(string node, const(Entitlement)[] list) {
      foreach (e; list) {
        ServicePlan p;
        if (!tryPlan(e.plan, p))
          error(node, "Entitlement for the unknown service plan '" ~ e.plan ~ "'");
      }
    }

    checkPlans("global", global.entitlements);
    foreach (d; directories)
      if (d.manageEntitlements)
        checkPlans("directory:" ~ d.key, d.entitlements);
    foreach (s; subaccounts)
      checkPlans("subaccount:" ~ s.key, s.entitlements);

    void checkConsumer(string node, string source, const(Entitlement)[] list) {
      foreach (e; list)
        if (!holds(source, e.plan))
          error(node, "Uses " ~ e.plan ~ ", which " ~ label(source) ~ " is not entitled to");
        else if (quotaOf(source, e.plan) != unlimited && e.quota == unlimited)
          error(node, "Takes " ~ e.plan ~ " without limit, but " ~ label(source) ~ " only has "
              ~ quotaOf(source, e.plan).to!string);
    }

    foreach (d; directories)
      if (d.manageEntitlements)
        checkConsumer("directory:" ~ d.key, sourceOf(d), d.entitlements);
    foreach (s; subaccounts)
      checkConsumer("subaccount:" ~ s.key, sourceOf(s), s.entitlements);

    string[] sources = ["global"];
    foreach (d; directories)
      if (d.manageEntitlements)
        sources ~= "directory:" ~ d.key;
    foreach (source; sources)
      foreach (e; entitlementsOf(source)) {
        if (e.quota == unlimited)
          continue;
        bool open;
        auto assigned = assignedFrom(source, e.plan, open);
        if (assigned > e.quota)
          error(source, e.plan ~ ": " ~ assigned.to!string ~ " assigned below, but only " ~ e.quota.to!string
              ~ " available");
      }
    return issues;
  }

  /// Recommendations: where directory entitlements and role collections
  /// help, and where they hurt.
  Advice[] advise() const pure {
    Advice[] advice;
    void add(string node, string topic, string recommendation, string reason) {
      advice ~= Advice(node, topic, recommendation, reason);
    }

    foreach (d; directories) {
      auto node = "directory:" ~ d.key;
      auto below = subaccountsBelow(d.key);
      auto stages = below.map!(s => s.stage).array.sort.uniq.array;
      auto mixedStages = below.any!(s => s.stage.isProduction) && below.any!(s => !s.stage.isProduction);
      auto domains = below.map!(s => s.domain).array.sort.uniq.array;
      auto ownBudget = d.costCenter.length > 0 && d.costCenter != global.costCenter;

      // entitlements
      if (!d.manageEntitlements && below.length >= 2 && (ownBudget || d.owner.length))
        add(node, "entitlements", "Enable directory entitlements",
          "It groups " ~ below.length.to!string ~ " subaccounts with " ~ (ownBudget ? "its own cost center ("
            ~ d.costCenter ~ ")" : "its own owner (" ~ d.owner ~ ")") ~ ": give it a budget once and let its "
          ~ "owner distribute it, instead of entitling each subaccount from the global account.");
      if (d.manageEntitlements && below.length <= 1)
        add(node, "entitlements", "Disable directory entitlements",
          "It holds " ~ below.length.to!string ~ " subaccount" ~ (below.length == 1 ? "" : "s")
          ~ "; an extra budget level only adds bookkeeping. Entitle the subaccount directly.");
      if (d.manageEntitlements && !d.costCenter.length && !d.owner.length)
        add(node, "entitlements", "Name an owner or cost center",
          "A directory budget needs someone who answers for it.");

      // authorizations
      if (d.manageAuthorizations && mixedStages)
        foreach (rc; d.roleCollections)
          if (rc.members.length && rc.rights.any!(r => r.canFind(".manage")))
            add(node, "authorizations", "Move '" ~ rc.name ~ "' to the subaccounts or split the directory",
              "It grants changing rights in production and non-production subaccounts at once (stages: "
              ~ stages.map!(s => s.to!string).join(", ") ~ "). Keep production access separate (segregation "
              ~ "of duties).");
      if (!d.manageAuthorizations && below.length >= 2) {
        foreach (rc; below[0].roleCollections) {
          auto same = below.all!(s => s.roleCollections.any!(x => x.name == rc.name && x.members == rc.members));
          if (same && !mixedStages)
            add(node, "authorizations", "Define '" ~ rc.name ~ "' once on the directory",
              "All " ~ below.length.to!string ~ " subaccounts below hold the same role collection with the same "
              ~ "members; a directory role collection keeps them in step.");
        }
      }
      if (d.manageAuthorizations && d.roleCollections.length == 0)
        add(node, "authorizations", "Disable directory authorizations or add role collections",
          "The feature is on, but nothing is defined at this level.");

      // structure
      if (domains.length > 1)
        add(node, "security", "Separate the security domains",
          "Subaccounts of the domains " ~ domains.map!(x => x.to!string).join(", ")
          ~ " share this directory; one directory per domain keeps budgets and authorizations apart.");
      if (below.length == 0)
        add(node, "structure", "Add subaccounts or remove the directory", "It contains no subaccount.");
    }

    foreach (s; subaccounts) {
      auto node = "subaccount:" ~ s.key;
      RegionInfo region;
      auto known = tryRegion(s.region, region);
      if (s.stage.isProduction && s.betaFeatures)
        add(node, "security", "Turn off beta features", "Beta services are not meant for production.");
      if ((s.domain == SecurityDomain.confidential || s.domain == SecurityDomain.secret) && known && !region.euAccess
          && region.provider != "Self-hosted")
        add(node, "security", "Consider an EU Access or self-hosted region",
          "It is in the " ~ s.domain.to!string ~ " domain but runs in " ~ region.location ~ ".");
      if (s.stage.isProduction && s.roleCollections.any!(rc => rc.members.length > 5
          && rc.rights.any!(r => r.canFind(".manage"))))
        add(node, "authorizations", "Reduce production administrators",
          "More than five people can change production; prefer named, few administrators.");
      foreach (a; recoveryAdvice(s))
        add(node, "recovery", a.recommendation, a.reason);
    }
    if (directories.length && subaccounts.any!(s => s.directory.length == 0))
      add("global", "structure", "Place the remaining subaccounts in directories",
        "Some subaccounts sit directly below the global account while directories exist; they miss the "
        ~ "directory's budget and governance.");
    if (global.roleCollections.any!(rc => rc.members.length > 3))
      add("global", "authorizations", "Keep global role collections small",
        "Global role collections reach every subaccount; delegate to directories where possible.");
    return advice;
  }

  // ── authority ───────────────────────────────────────────────────────────

  /// A global account administrator: everything in this global account.
  bool isGlobalAdmin(string user) const pure nothrow {
    return user.length > 0 && global.admins.canFind(user);
  }

  /// Global account administrators and the administrators of the subaccount.
  bool mayAdminister(string subaccountKey, string user) const pure nothrow {
    if (isGlobalAdmin(user))
      return true;
    Subaccount s;
    return user.length > 0 && trySubaccount(subaccountKey, s) && s.isAdmin(user);
  }

  /// Keys of the subaccounts whose administrators or user group name `user`.
  string[] subaccountsOf(string user) const pure nothrow {
    string[] list;
    foreach (s; subaccounts)
      if (s.isUser(user))
        list ~= s.key;
    return list;
  }

  // ── service calls ───────────────────────────────────────────────────────

  /// The subaccount with this key or subdomain.
  bool trySubaccountByName(string keyOrSubdomain, out Subaccount s) const pure nothrow {
    foreach (x; subaccounts)
      if (x.key == keyOrSubdomain || x.subdomain == keyOrSubdomain) {
        s = x.copy;
        return true;
      }
    return false;
  }

  /// The tenant and space a service call runs in. In order:
  ///   headers   X-Neko-Subaccount (key or subdomain), X-Neko-Tenant, X-Neko-Space
  ///   host      <subaccount-subdomain>.… (default tenant) or <tenant>.<subaccount-subdomain>.…
  ///   default   the default tenant of the first subaccount
  /// The space is the one named, else the default space.
  /// Throws NotFoundException for a subaccount, tenant or space that does not
  /// exist, ValidationException for a tenant that is ambiguous.
  CallContext resolveCall(const CallRequest r) const pure {
    CallContext c;
    Subaccount sub;
    auto haveSub = false;
    auto tenant = r.tenant.strip.toLower;
    auto space = r.space.strip.toLower;

    if (r.subaccount.strip.length) {
      if (!trySubaccountByName(r.subaccount.strip.toLower, sub))
        throw new NotFoundException("Subaccount", r.subaccount.strip);
      haveSub = true;
      c.source = "header";
    }
    if (!haveSub && r.host.length) {
      auto labels = r.host.toLower.split(".");
      if (labels.length >= 2 && trySubaccountByName(labels[0], sub) && sub.subdomain == labels[0]) {
        haveSub = true;
        c.source = "subdomain";
      } else if (labels.length >= 3 && trySubaccountByName(labels[1], sub) && sub.subdomain == labels[1]) {
        haveSub = true;
        c.source = "subdomain";
        if (tenant.length == 0)
          tenant = labels[0];
      }
    }
    if (!haveSub && tenant.length) {
      // a tenant header alone: the subaccount that has it
      Subaccount[] owners;
      foreach (x; subaccounts) {
        Tenant t;
        if (x.tryTenant(tenant, t))
          owners ~= x.copy;
      }
      if (owners.length == 0)
        throw new NotFoundException("Tenant", tenant);
      if (owners.length > 1)
        throw new ValidationException("The tenant '" ~ tenant ~ "' exists in several subaccounts; name the "
            ~ "subaccount (X-Neko-Subaccount)");
      sub = owners[0];
      haveSub = true;
      c.source = "header";
    }
    if (!haveSub) {
      if (subaccounts.length == 0)
        throw new NotFoundException("Subaccount", "(none)");
      sub = subaccounts[0].copy;
      c.source = "default";
    }

    Tenant t;
    if (tenant.length) {
      if (!sub.tryTenant(tenant, t))
        throw new NotFoundException("Tenant", sub.key ~ "/" ~ tenant);
      if (c.source != "subdomain")
        c.source = "header";
    } else if (!sub.tryDefaultTenant(t))
      throw new NotFoundException("Tenant", sub.key ~ "/(default)");

    Space sp;
    if (space.length) {
      if (!t.trySpace(space, sp))
        throw new NotFoundException("Space", sub.key ~ "/" ~ t.key ~ "/" ~ space);
    } else if (!t.trySpace(defaultSpaceKey, sp))
      throw new NotFoundException("Space", sub.key ~ "/" ~ t.key ~ "/" ~ defaultSpaceKey);

    c.subaccount = sub.key;
    c.subdomain = sub.subdomain;
    c.region = activeRegion(sub);
    c.tenant = t.key;
    c.space = sp.key;
    return c;
  }

  /// "the global account", "directory shop"
  string label(string node) const pure {
    if (node == "global")
      return "the global account";
    if (node.length > 10 && node[0 .. 10] == "directory:")
      return "directory " ~ node[10 .. $];
    if (node.length > 11 && node[0 .. 11] == "subaccount:")
      return "subaccount " ~ node[11 .. $];
    return node;
  }
}

///
unittest {
  Landscape l;
  l.global.subdomainPrefix = "acme";
  l.global.costCenter = "CC-100";
  l.plans = defaultPlans();
  l.global.entitlements = [Entitlement("support.premium", 10), Entitlement("platform.requests", unlimited)];
  Directory shop;
  shop.key = "shop";
  shop.costCenter = "CC-200";
  shop.manageEntitlements = true;
  shop.entitlements = [Entitlement("support.premium", 6)];
  Directory eu;
  eu.key = "shop-eu";
  eu.parent = "shop";
  l.directories = [shop, eu];

  Subaccount dev, prod;
  dev.key = "shop-dev";
  dev.directory = "shop-eu";
  dev.purpose = "shop";
  dev.stage = Stage.dev;
  dev.entitlements = [Entitlement("support.premium", 2)];
  prod = dev;
  prod.key = "shop-prod";
  prod.stage = Stage.prod;
  prod.entitlements = [Entitlement("support.premium", 3)];
  dev.subdomain = subdomainFor(l.global, dev, "shop-eu");
  prod.subdomain = subdomainFor(l.global, prod, "shop-eu");
  dev.ensureTenancy(SysTime.init);
  prod.ensureTenancy(SysTime.init);
  l.global.admins = ["root"];
  l.subaccounts = [dev, prod];

  assert(dev.subdomain == "acme-shop-dev" && prod.subdomain == "acme-shop-prod");
  assert(l.depth("shop-eu") == 2 && l.sourceOf(prod) == "directory:shop" && l.sourceOf(shop) == "global");
  bool open;
  assert(l.assignedFrom("directory:shop", "support.premium", open) == 5
      && l.assignedFrom("global", "support.premium", open) == 6);
  assert(l.validate().length == 0, l.validate().map!(i => i.message).join("; "));
  assert(l.costCenterOf(prod) == "CC-200");

  // over-assignment and entitlements the source does not hold
  l.subaccounts[1].entitlements = [Entitlement("support.premium", 5), Entitlement("files.storage", 2)];
  auto issues = l.validate();
  assert(issues.any!(i => i.node == "directory:shop" && i.message.canFind("7 assigned")));
  assert(issues.any!(i => i.node == "subaccount:shop-prod" && i.message.canFind("files.storage")));

  // advice: one subaccount under a directory budget, mixed stages with changing rights
  l.subaccounts[1].entitlements = [Entitlement("support.premium", 3)];
  l.directories[0].manageAuthorizations = true;
  l.directories[0].roleCollections = [RoleCollection("Shop Admin", "", ["files.manage"], ["jane"])];
  auto advice = l.advise();
  assert(advice.any!(a => a.topic == "authorizations" && a.recommendation.canFind("Shop Admin")));
  l.directories[1].costCenter = "CC-300";
  assert(l.advise().any!(a => a.node == "directory:shop-eu" && a.recommendation == "Enable directory entitlements"));

  assert(parseStage("Production") == Stage.prod && landscapeKey(" Shop-EU ", "x") == "shop-eu");
  assert(subdomainLabel("Acme-Dev") == "acme-dev");
  bool failed;
  try
    subdomainLabel("-bad");
  catch (ValidationException)
    failed = true;
  assert(failed);
  GlobalAccount g;
  g.subdomainPattern = "{global}-{directory}-{purpose}-{stage}";
  Subaccount bare;
  bare.key = "x1";
  assert(subdomainFor(g, bare, "") == "neko-x1-dev");
}

/// Tenants, spaces, user groups, services and service calls.
unittest {
  Landscape l;
  l.global.admins = ["root"];
  Subaccount shop;
  shop.key = "shop-prod";
  shop.subdomain = "acme-shop-prod";
  shop.ensureTenancy(SysTime.init);
  assert(shop.tenants.length == 1 && shop.tenants[0].isDefault && shop.tenants[0].spaces[0].key == defaultSpaceKey);
  auto eu = Tenant("eu", "Europe");
  eu.ensureDefaultSpace(SysTime.init);
  eu.spaces ~= Space("staging", "Staging");
  shop.tenants ~= eu;
  shop.admins = ["ann"];
  shop.members = ["bob"];
  shop.services = ["files", "landscape"];
  Subaccount other;
  other.key = "blog";
  other.subdomain = "acme-blog";
  other.ensureTenancy(SysTime.init);
  l.subaccounts = [other, shop];
  assert(l.validate().length == 0, l.validate().map!(i => i.message).join("; "));
  assert(l.mayAdminister("shop-prod", "ann") && l.mayAdminister("blog", "root"));
  assert(!l.mayAdminister("blog", "ann") && l.subaccountsOf("bob") == ["shop-prod"]);

  // role collections: members of the user group, rights of the selected services
  l.subaccounts[1].roleCollections = [RoleCollection("Editors", "", ["files.manage"], ["bob"])];
  assert(l.validate().length == 0);
  l.subaccounts[1].roleCollections = [RoleCollection("Editors", "", ["users.manage"], ["eve"])];
  auto issues = l.validate();
  assert(issues.length == 2 && issues.any!(i => i.message.canFind("eve")) && issues.any!(i => i.message.canFind("users")));
  l.subaccounts[1].roleCollections = null;

  // broken tenancy
  auto broken = l.copy;
  broken.subaccounts[1].tenants[1].isDefault = true;
  broken.subaccounts[1].tenants[1].spaces = broken.subaccounts[1].tenants[1].spaces[1 .. $];
  auto bad = broken.validate().map!(i => i.message).join("; ");
  assert(bad.canFind("exactly one default tenant") && bad.canFind("no space 'default'"));

  // service calls
  CallContext call(string host, string sub = "", string tenant = "", string space = "") {
    return l.resolveCall(CallRequest(host, sub, tenant, space));
  }

  auto c = call("acme-shop-prod.neko.example");
  assert(c.subaccount == "shop-prod" && c.tenant == "default" && c.space == "default" && c.source == "subdomain");
  c = call("eu.acme-shop-prod.neko.example", "", "", "staging");
  assert(c.tenant == "eu" && c.space == "staging" && c.subdomain == "acme-shop-prod");
  c = call("localhost", "", "eu");
  assert(c.subaccount == "shop-prod" && c.tenant == "eu" && c.space == "default" && c.source == "header");
  c = call("localhost");
  assert(c.subaccount == "blog" && c.source == "default");
  c = call("localhost", "acme-shop-prod");
  assert(c.subaccount == "shop-prod" && c.tenant == "default");
  bool notFound(string tenant, string space) {
    try
      call("acme-shop-prod.x", "", tenant, space);
    catch (NotFoundException)
      return true;
    return false;
  }

  assert(notFound("nope", "") && notFound("eu", "nope") && !notFound("eu", "staging"));
  bool ambiguous;
  try
    call("localhost", "", "default");
  catch (ValidationException)
    ambiguous = true;
  assert(ambiguous);
  assert(serviceCatalogue().any!(x => x.key == "files" && x.rights == ["files.read", "files.manage"]));
}

/// A deep copy (const → mutable).
Landscape copy(const Landscape l) pure nothrow {
  Landscape r;
  r.global = l.global.copy;
  foreach (d; l.directories)
    r.directories ~= d.copy;
  foreach (s; l.subaccounts)
    r.subaccounts ~= s.copy;
  r.plans = l.plans.dup;
  return r;
}
