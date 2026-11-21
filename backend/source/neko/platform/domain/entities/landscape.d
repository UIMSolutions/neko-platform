/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The account hierarchy, modelled on SAP BTP:
///
///   Global Account   governance: contract, cost center, the purchased
///                    entitlements (service plans and quotas), global role
///                    collections, the subdomain scheme
///   Directories      group subaccounts (nested up to `maxDirectoryDepth`);
///                    optionally manage their own entitlements (a budget that
///                    their subaccounts draw from) and role collections
///   Subaccounts      where things run: region, subdomain, purpose, stage,
///                    security domain, the sites (tenants) of this instance
///
/// Entitlements flow down: a subaccount draws from the nearest directory
/// above it that manages entitlements, else from the global account; such a
/// directory itself draws from the next level up. `validate` reports
/// over-assignment and broken rules; `advise` recommends where directory
/// entitlements and role collections help — and where they do not.
module neko.platform.domain.entities.landscape;

import std.algorithm : any, all, canFind, count, filter, map, sort, sum, uniq;
import std.array : array, join, replace;
import std.ascii : isDigit, isLower;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.string : strip, toLower;
import neko.platform.domain.enumerations.security : SecurityDomain;
import neko.platform.domain.exceptions;

@safe:

enum maxDirectoryDepth = 5;
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
  /// Access right keys ("sites.manage").
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
  /// Keys of the sites (tenants) of this platform instance it hosts.
  string[] sites;
  /// "" = inherited from the directory / global account.
  string costCenter;
  bool betaFeatures;
  Entitlement[] entitlements;
  RoleCollection[] roleCollections;
  SysTime createdAt;
  SysTime modifiedAt;

  Subaccount copy() const pure nothrow {
    return Subaccount(key, name, description, directory, region, subdomain, purpose, stage, domain, sites.dup,
      costCenter, betaFeatures, entitlements.dup, copyAll(roleCollections), createdAt, modifiedAt);
  }
}

/// What a unit of a service plan is measured with.
enum Meter {
  /// Not measured: billed by the entitled quota (a fixed monthly fee per unit).
  none,
  /// Requests to the sites of the subaccount.
  requests,
  /// Bytes sent by the sites of the subaccount.
  egressBytes,
  /// Peak bytes of the files of its sites in the month.
  storageBytes,
  /// Sites assigned to the subaccount.
  sites,
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
    ServicePlan("platform.requests", "Platform", "requests", "Requests to the sites of a subaccount",
      "1,000 requests", 1000, 0.04, Meter.requests),
    ServicePlan("network.egress", "Network", "egress", "Data sent by the sites of a subaccount", "GB", gib, 0.09,
      Meter.egressBytes),
    ServicePlan("files.storage", "Files", "standard", "Peak size of the site files in the month", "GB-month", gib,
      0.025, Meter.storageBytes),
    ServicePlan("sites.site", "Sites", "site", "Sites (tenants) hosted by the subaccount", "site-month", 1, 5,
      Meter.sites),
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
  /// "entitlements" | "authorizations" | "structure" | "security"
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

  /// The subaccount hosting `site`, if any.
  bool tryHost(string site, out Subaccount s) const pure nothrow {
    foreach (x; subaccounts)
      if (x.sites.canFind(site)) {
        s = x.copy;
        return true;
      }
    return false;
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
      foreach (other; subaccounts)
        if (other.key < s.key)
          foreach (site; s.sites)
            if (other.sites.canFind(site))
              error(node, "The site '" ~ site ~ "' is also assigned to " ~ other.key);
    }

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

    // sites are counted, not metered over time: the quota is a hard limit
    foreach (s; subaccounts)
      foreach (e; s.entitlements) {
        ServicePlan p;
        if (tryPlan(e.plan, p) && p.meter == Meter.sites && e.quota != unlimited && s.sites.length > e.quota)
          error("subaccount:" ~ s.key, "Hosts " ~ s.sites.length.to!string ~ " sites, but is entitled to "
              ~ e.quota.to!string ~ " (" ~ e.plan ~ ")");
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
  l.global.entitlements = [Entitlement("sites.site", 10), Entitlement("platform.requests", unlimited)];
  Directory shop;
  shop.key = "shop";
  shop.costCenter = "CC-200";
  shop.manageEntitlements = true;
  shop.entitlements = [Entitlement("sites.site", 6)];
  Directory eu;
  eu.key = "shop-eu";
  eu.parent = "shop";
  l.directories = [shop, eu];

  Subaccount dev, prod;
  dev.key = "shop-dev";
  dev.directory = "shop-eu";
  dev.purpose = "shop";
  dev.stage = Stage.dev;
  dev.entitlements = [Entitlement("sites.site", 2)];
  prod = dev;
  prod.key = "shop-prod";
  prod.stage = Stage.prod;
  prod.entitlements = [Entitlement("sites.site", 3)];
  dev.subdomain = subdomainFor(l.global, dev, "shop-eu");
  prod.subdomain = subdomainFor(l.global, prod, "shop-eu");
  l.subaccounts = [dev, prod];

  assert(dev.subdomain == "acme-shop-dev" && prod.subdomain == "acme-shop-prod");
  assert(l.depth("shop-eu") == 2 && l.sourceOf(prod) == "directory:shop" && l.sourceOf(shop) == "global");
  bool open;
  assert(l.assignedFrom("directory:shop", "sites.site", open) == 5 && l.assignedFrom("global", "sites.site", open) == 6);
  assert(l.validate().length == 0, l.validate().map!(i => i.message).join("; "));
  assert(l.costCenterOf(prod) == "CC-200");

  // over-assignment and entitlements the source does not hold
  l.subaccounts[1].entitlements = [Entitlement("sites.site", 5), Entitlement("files.storage", 2)];
  auto issues = l.validate();
  assert(issues.any!(i => i.node == "directory:shop" && i.message.canFind("7 assigned")));
  assert(issues.any!(i => i.node == "subaccount:shop-prod" && i.message.canFind("files.storage")));

  // advice: one subaccount under a directory budget, mixed stages with changing rights
  l.subaccounts[1].entitlements = [Entitlement("sites.site", 3)];
  l.directories[0].manageAuthorizations = true;
  l.directories[0].roleCollections = [RoleCollection("Shop Admin", "", ["sites.manage"], ["jane"])];
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
