/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The account hierarchy and billing (see domain.entities.landscape and
/// domain.entities.billing for the rules).
module neko.platform.application.usecases.manage_landscape;

import std.algorithm : any, canFind, countUntil, filter, map, remove, sort;
import std.array : array, join;
import std.conv : to;
import std.format : format;
import std.string : strip, toLower;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.ports;

@safe:

/// "2026-11" for a time.
string monthOf(SysTime t) {
  auto s = t.toUTC.toISOExtString;
  return s[0 .. 7];
}

import std.datetime.systime : SysTime;

class ManageLandscapeUseCase : IManageLandscapeUseCase, IBillingUseCase {
  private ILandscapeRepository repo;
  private IUsageRepository usage;
  private ISiteRepository sites;
  private IEventPublisher events;
  private IClock clock;
  private SecurityDomain domain;

  this(ILandscapeRepository repo, IUsageRepository usage, ISiteRepository sites, IEventPublisher events, IClock clock,
      SecurityDomain domain) {
    this.repo = repo;
    this.usage = usage;
    this.sites = sites;
    this.events = events;
    this.clock = clock;
    this.domain = domain;
  }

  // ── reading ─────────────────────────────────────────────────────────────

  Landscape landscape() {
    return repo.load();
  }

  // Service calls resolve their tenant on every request: they read a copy
  // that is refreshed after each change here and at least every 10 seconds
  // (changes by another process, e.g. the CLI).
  private Landscape cached;
  private SysTime cachedAt;
  private bool haveCache;

  private const(Landscape) current() {
    import core.time : seconds;

    auto now = clock.now;
    if (!haveCache || now - cachedAt > 10.seconds || now < cachedAt) {
      cached = repo.load();
      cachedAt = now;
      haveCache = true;
    }
    return cached;
  }

  private void invalidate() {
    haveCache = false;
  }

  CallContext resolveCall(CallRequest request) {
    return current().resolveCall(request);
  }

  bool isGlobalAdmin(string user) {
    return current().isGlobalAdmin(user);
  }

  bool mayAdminister(string subaccount, string user) {
    return current().mayAdminister(subaccount, user);
  }

  string[] grantedRights(string user) {
    auto l = current();
    if (l.isGlobalAdmin(user))
      return ["landscape.read", "landscape.manage", "billing.read"];
    if (l.subaccountsOf(user).length)
      return ["landscape.read"];
    return null;
  }

  LandscapeDto overview(string month = "") {
    auto l = repo.load();
    auto m = monthOrNow(month);
    auto bill = computeBill(l, m, usage.ofMonth(m));
    LandscapeDto d;
    d.month = m;
    d.currency = l.global.currency;
    d.plans = l.plans.dup;
    d.issues = l.validate();
    d.advice = l.advise();
    d.monthCost = bill.total;
    d.subaccounts = cast(long) l.subaccounts.length;
    d.directories = cast(long) l.directories.length;
    d.tree = tree(l, bill, d.issues, d.advice);
    return d;
  }

  NodeDto node(string node, string month = "") {
    auto l = repo.load();
    auto m = monthOrNow(month);
    return nodeDto(l, node, computeBill(l, m, usage.ofMonth(m)));
  }

  ServicePlan[] plans() {
    return repo.load().plans;
  }

  // ── changes ─────────────────────────────────────────────────────────────

  NodeDto updateGlobal(GlobalAccountRequest r, string actor) {
    auto l = repo.load();
    auto g = l.global.copy;
    auto name = r.name.strip;
    if (name.length == 0 || name.length > 128)
      throw new ValidationException("The name of the global account must have 1 to 128 characters");
    g.name = name;
    if (r.subdomainPrefix.strip.length)
      g.subdomainPrefix = subdomainLabel(r.subdomainPrefix);
    if (r.subdomainPattern.strip.length) {
      auto pattern = r.subdomainPattern.strip.toLower;
      if (!pattern.canFind("{purpose}") && !pattern.canFind("{stage}"))
        throw new ValidationException("The subdomain scheme needs {purpose} or {stage}, or every subaccount gets the "
            ~ "same subdomain");
      g.subdomainPattern = pattern;
    }
    if (r.contract.strip.length) {
      auto c = r.contract.strip;
      if (!["CPEA", "PAYG", "subscription"].canFind(c))
        throw new ValidationException("Contract must be CPEA, PAYG or subscription");
      g.contract = c;
    }
    if (r.currency.strip.length) {
      auto cur = r.currency.strip.toUpper3;
      g.currency = cur;
    }
    g.costCenter = r.costCenter.strip;
    g.admins = r.admins.map!(a => a.strip).filter!(a => a.length > 0).array;
    g.modifiedAt = clock.now;
    change(l, (ref Landscape x) { x.global = g; });
    repo.saveGlobal(g);
    emit("landscape.global.changed", "global", actor, "Changed the global account " ~ g.name);
    return node("global");
  }

  NodeDto saveDirectory(DirectoryRequest r, bool create, string actor) {
    auto l = repo.load();
    auto key = landscapeKey(r.key, "Directory");
    Directory d;
    auto exists = l.tryDirectory(key, d);
    if (create && exists)
      throw new ConflictException("A directory '" ~ key ~ "' already exists");
    if (!create && !exists)
      throw new NotFoundException("Directory", key);
    Subaccount clash;
    if (create && l.trySubaccount(key, clash))
      throw new ConflictException("A subaccount is already called '" ~ key ~ "'");
    auto now = clock.now;
    if (create) {
      d.key = key;
      d.createdAt = now;
    }
    d.name = requireName(r.name, key);
    d.description = r.description.strip;
    auto parent = r.parent.strip.toLower;
    if (parent.length) {
      Directory p;
      if (!l.tryDirectory(parent, p))
        throw new ValidationException("The parent directory '" ~ parent ~ "' does not exist");
      if (parent == key || l.ancestors(parent).any!(a => a.key == key))
        throw new ValidationException("A directory cannot be moved below itself");
    }
    d.parent = parent;
    d.manageEntitlements = r.manageEntitlements;
    d.manageAuthorizations = r.manageAuthorizations;
    d.costCenter = r.costCenter.strip;
    d.owner = r.owner.strip;
    d.modifiedAt = now;
    change(l, (ref Landscape x) {
      auto i = x.directories.countUntil!(e => e.key == key);
      if (i < 0)
        x.directories ~= d.copy;
      else
        x.directories[i] = d.copy;
    });
    repo.saveDirectory(d);
    emit(create ? "landscape.directory.created" : "landscape.directory.changed", key, actor,
      (create ? "Created" : "Changed") ~ " directory " ~ key ~ features(d));
    return node("directory:" ~ key);
  }

  void removeDirectory(string key, string actor) {
    auto l = repo.load();
    Directory d;
    if (!l.tryDirectory(key.strip, d))
      throw new NotFoundException("Directory", key);
    auto children = l.directories.filter!(x => x.parent == d.key).map!(x => x.key).array
      ~ l.subaccounts.filter!(x => x.directory == d.key).map!(x => x.key).array;
    if (children.length)
      throw new ConflictException("The directory '" ~ d.key ~ "' still contains " ~ children.join(", ")
          ~ "; move or remove them first");
    repo.removeDirectory(d.key);
    emit("landscape.directory.removed", d.key, actor, "Removed directory " ~ d.key);
  }

  NodeDto saveSubaccount(SubaccountRequest r, bool create, string actor) {
    auto l = repo.load();
    auto key = landscapeKey(r.key, "Subaccount");
    Subaccount s;
    auto exists = l.trySubaccount(key, s);
    if (create && exists)
      throw new ConflictException("A subaccount '" ~ key ~ "' already exists");
    if (!create && !exists)
      throw new NotFoundException("Subaccount", key);
    Directory clash;
    if (create && l.tryDirectory(key, clash))
      throw new ConflictException("A directory is already called '" ~ key ~ "'");
    auto now = clock.now;
    if (create) {
      s.key = key;
      s.createdAt = now;
    }
    s.name = requireName(r.name, key);
    s.description = r.description.strip;
    auto dir = r.directory.strip.toLower;
    Directory parent;
    if (dir.length && !l.tryDirectory(dir, parent))
      throw new ValidationException("The directory '" ~ dir ~ "' does not exist");
    s.directory = dir;
    s.purpose = r.purpose.strip.length ? subdomainLabel(r.purpose) : "";
    s.stage = parseStage(r.stage.length ? r.stage : "dev");
    if (r.domain.strip.length) {
      SecurityDomain d;
      if (!tryParseSecurityDomain(r.domain.strip.toLower, d))
        throw new ValidationException("Unknown security domain '" ~ r.domain ~ "'");
      s.domain = d;
    } else if (create)
      s.domain = domain;
    s.costCenter = r.costCenter.strip;
    s.betaFeatures = r.betaFeatures;

    // Region and subdomain are fixed once the subaccount exists (as in SAP BTP).
    auto region = r.region.strip.toLower;
    if (create) {
      RegionInfo info;
      if (!tryRegion(region, info))
        throw new ValidationException("Unknown region '" ~ r.region ~ "'");
      s.region = region;
      s.subdomain = r.subdomain.strip.length ? subdomainLabel(r.subdomain)
        : subdomainLabel(subdomainFor(l.global, s, dir));
    } else {
      if (region.length && region != s.region)
        throw new InvalidStateTransitionException("The region of a subaccount cannot change; create a new subaccount");
      if (r.subdomain.strip.length && subdomainLabel(r.subdomain) != s.subdomain)
        throw new InvalidStateTransitionException("The subdomain of a subaccount cannot change; it is part of every URL");
    }

    if (create)
      s.ensureTenancy(now);
    if (s.sites.length && s.domain != domain)
      throw new ValidationException("Sites of this instance (" ~ domain.label ~ ") can only be hosted by a subaccount of "
          ~ "the " ~ domain.label ~ " domain; " ~ s.key ~ " hosts " ~ s.sites.join(", "));
    s.modifiedAt = now;
    change(l, (ref Landscape x) {
      auto i = x.subaccounts.countUntil!(e => e.key == key);
      if (i < 0)
        x.subaccounts ~= s.copy;
      else
        x.subaccounts[i] = s.copy;
    });
    repo.saveSubaccount(s);
    emit(create ? "landscape.subaccount.created" : "landscape.subaccount.changed", key, actor,
      (create ? "Created" : "Changed") ~ " subaccount " ~ key ~ " (" ~ s.region ~ ", " ~ s.subdomain ~ ", "
        ~ s.stage.to!string ~ ")");
    return node("subaccount:" ~ key);
  }

  void removeSubaccount(string key, string actor) {
    auto l = repo.load();
    Subaccount s;
    if (!l.trySubaccount(key.strip, s))
      throw new NotFoundException("Subaccount", key);
    if (s.sites.length)
      throw new ConflictException("The subaccount '" ~ s.key ~ "' still hosts " ~ s.sites.join(", ")
          ~ "; assign the sites elsewhere first");
    repo.removeSubaccount(s.key);
    emit("landscape.subaccount.removed", s.key, actor, "Removed subaccount " ~ s.key);
  }

  NodeDto setEntitlement(string node, string plan, long quota, bool remove, string actor) {
    auto l = repo.load();
    ServicePlan p;
    if (!l.tryPlan(plan.strip, p))
      throw new ValidationException("Unknown service plan '" ~ plan ~ "'");
    if (!remove && quota < unlimited)
      throw new ValidationException("The quota must be 0 or more, or unlimited");
    if (node.length > 10 && node[0 .. 10] == "directory:") {
      Directory d;
      if (l.tryDirectory(node[10 .. $], d) && !d.manageEntitlements)
        throw new ValidationException("The directory " ~ d.key ~ " does not manage entitlements; enable it first");
    }
    auto entry = Entitlement(p.key, quota);
    change(l, (ref Landscape x) { patchEntitlements(x, node, entry, remove); });
    persist(l, node, (ref Landscape x) { patchEntitlements(x, node, entry, remove); });
    emit("landscape.entitlement", node, actor, remove ? "Removed " ~ p.key ~ " from " ~ l.label(node)
        : "Entitled " ~ l.label(node) ~ " to " ~ (quota == unlimited ? "unlimited" : quota.to!string) ~ " " ~ p.unit
        ~ " of " ~ p.key);
    return this.node(node);
  }

  NodeDto saveRoleCollection(string node, RoleCollectionRequest r, string actor) {
    auto l = repo.load();
    auto name = r.name.strip;
    if (name.length == 0 || name.length > 64)
      throw new ValidationException("The name of a role collection must have 1 to 64 characters");
    string[] rights;
    foreach (k; r.rights) {
      AccessRight right;
      if (!tryParseAccessRight(k.strip, right))
        throw new ValidationException("Unknown access right '" ~ k ~ "'");
      if (!rights.canFind(right.key))
        rights ~= right.key;
    }
    string[] members;
    foreach (m; r.members)
      if (m.strip.length) {
        auto user = UserName(m).value;
        if (!members.canFind(user))
          members ~= user;
      }
    if (node.length > 10 && node[0 .. 10] == "directory:") {
      Directory d;
      if (l.tryDirectory(node[10 .. $], d) && !d.manageAuthorizations)
        throw new ValidationException("The directory " ~ d.key ~ " does not manage authorizations; enable it first");
    }
    auto rc = RoleCollection(name, r.description.strip, rights, members.sort.array);
    persist(l, node, (ref Landscape x) { patchCollections(x, node, rc, false); });
    emit("landscape.rolecollection", node, actor, "Saved role collection '" ~ name ~ "' at " ~ l.label(node) ~ " ("
        ~ members.length.to!string ~ " members)");
    return this.node(node);
  }

  NodeDto removeRoleCollection(string node, string name, string actor) {
    auto l = repo.load();
    persist(l, node, (ref Landscape x) { patchCollections(x, node, RoleCollection(name.strip), true); });
    emit("landscape.rolecollection.removed", node, actor, "Removed role collection '" ~ name ~ "' from "
        ~ l.label(node));
    return this.node(node);
  }

  ServicePlan savePlan(ServicePlanRequest r, string actor) {
    auto key = landscapeKey(r.key, "Service plan");
    auto p = ServicePlan(key, r.service.strip, r.plan.strip, r.description.strip, r.unit.strip, r.unitSize, r.price);
    if (p.service.length == 0 || p.plan.length == 0 || p.unit.length == 0)
      throw new ValidationException("Service, plan and unit are required");
    if (!(r.unitSize > 0) || r.price < 0)
      throw new ValidationException("The unit size must be positive and the price not negative");
    switch (r.meter.strip) {
    case "", "none":
      p.meter = Meter.none;
      break;
    case "requests":
      p.meter = Meter.requests;
      break;
    case "egressBytes":
      p.meter = Meter.egressBytes;
      break;
    case "storageBytes":
      p.meter = Meter.storageBytes;
      break;
    case "sites":
      p.meter = Meter.sites;
      break;
    default:
      throw new ValidationException("Unknown meter '" ~ r.meter ~ "'");
    }
    repo.savePlan(p);
    emit("landscape.plan.saved", key, actor, "Saved service plan " ~ key ~ format(" (%.4g %s per %s)", p.price,
        repo.load().global.currency, p.unit));
    return p;
  }

  void removePlan(string key, string actor) {
    auto l = repo.load();
    ServicePlan p;
    if (!l.tryPlan(key.strip, p))
      throw new NotFoundException("Service plan", key);
    string[] users;
    foreach (node; nodes(l))
      if (l.holds(node, p.key))
        users ~= l.label(node);
    if (users.length)
      throw new ConflictException("The plan " ~ p.key ~ " is entitled to " ~ users.join(", ") ~ "; remove those first");
    repo.removePlan(p.key);
    emit("landscape.plan.removed", p.key, actor, "Removed service plan " ~ p.key);
  }

  void ensureDefaults(string serviceName, string environment, string defaultSite, string[] admins = null) {
    auto l = repo.load();
    if (l.plans.length == 0)
      foreach (p; defaultPlans())
        repo.savePlan(p);
    if (l.global.modifiedAt == SysTime.init) {
      GlobalAccount g;
      g.name = serviceName;
      g.subdomainPrefix = subdomainLabel(serviceName.toLower.replaceNonLabel);
      g.entitlements = [Entitlement("platform.requests", unlimited), Entitlement("network.egress", unlimited),
        Entitlement("files.storage", 100), Entitlement("sites.site", 10)];
      g.admins = admins.dup;
      g.modifiedAt = clock.now;
      repo.saveGlobal(g);
      l.global = g;
    }
    if (l.subaccounts.length == 0) {
      Subaccount s;
      s.key = "platform-" ~ domain.label;
      s.name = serviceName ~ " (" ~ domain.label ~ ")";
      s.description = "Runs this platform instance";
      s.purpose = "platform";
      s.stage = environment == "production" ? Stage.prod : Stage.dev;
      s.domain = domain;
      s.region = "eu10";
      s.subdomain = subdomainLabel(subdomainFor(l.global, s, "") ~ (domain == SecurityDomain.open ? "" : "-"
          ~ domain.label));
      s.createdAt = clock.now;
      s.ensureTenancy(s.createdAt);
      Site site;
      if (defaultSite.length && sites.tryGet(defaultSite, site))
        s.tenants[0].spaces[0].sites = [defaultSite];
      s.entitlements = [Entitlement("platform.requests", unlimited), Entitlement("network.egress", unlimited),
        Entitlement("files.storage", 50), Entitlement("sites.site", 5)];
      s.modifiedAt = s.createdAt;
      repo.saveSubaccount(s);
    }
    invalidate();
  }

  // ── subaccount access, tenants and spaces ───────────────────────────────

  NodeDto setSubaccountAccess(string key, SubaccountAccessRequest r, string actor) {
    auto l = repo.load();
    auto id = "subaccount:" ~ key.strip;
    auto admins = userNames(r.admins), members = userNames(r.members);
    string[] services;
    foreach (svc; r.services) {
      auto k = svc.strip.toLower;
      if (k.length == 0 || services.canFind(k))
        continue;
      if (!serviceCatalogue().any!(x => x.key == k))
        throw new ValidationException("Unknown service '" ~ svc ~ "'");
      services ~= k;
    }
    persist(l, id, (ref Landscape x) {
      auto s = subaccountRef(x, key.strip);
      s.admins = admins;
      s.members = members.filter!(m => !admins.canFind(m)).array;
      s.services = services.sort.array;
      s.modifiedAt = clock.now;
    });
    emit("landscape.subaccount.access", key, actor, "Changed the administrators (" ~ admins.join(", ") ~ "), the user "
        ~ "group (" ~ members.length.to!string ~ " members) and the services (" ~ (services.length ? services.join(", ")
        : "all") ~ ") of subaccount " ~ key);
    return node(id);
  }

  NodeDto saveTenant(string subaccount, TenantRequest r, bool create, string actor) {
    auto l = repo.load();
    auto key = subdomainLabel(r.key);
    if (key.length < 2)
      throw new ValidationException("A tenant key needs at least 2 characters");
    auto now = clock.now;
    persist(l, "subaccount:" ~ subaccount.strip, (ref Landscape x) {
      auto s = subaccountRef(x, subaccount.strip);
      auto i = s.tenants.countUntil!(t => t.key == key);
      if (create && i >= 0)
        throw new ConflictException("The subaccount " ~ s.key ~ " already has a tenant '" ~ key ~ "'");
      if (!create && i < 0)
        throw new NotFoundException("Tenant", s.key ~ "/" ~ key);
      Tenant t;
      if (create) {
        t.key = key;
        t.createdAt = now;
        t.ensureDefaultSpace(now);
      } else
        t = s.tenants[i];
      t.name = requireName(r.name, key);
      t.description = r.description.strip;
      t.modifiedAt = now;
      if (r.isDefault)
        foreach (ref other; s.tenants)
          other.isDefault = false;
      if (r.isDefault)
        t.isDefault = true;
      else if (!create && t.isDefault)
        throw new ValidationException("Make another tenant the default instead; a subaccount always has one");
      if (i < 0)
        s.tenants ~= t;
      else
        s.tenants[i] = t;
      s.modifiedAt = now;
    });
    emit(create ? "landscape.tenant.created" : "landscape.tenant.changed", subaccount ~ "/" ~ key, actor,
      (create ? "Created" : "Changed") ~ " tenant " ~ key ~ " of subaccount " ~ subaccount);
    return node("subaccount:" ~ subaccount.strip);
  }

  NodeDto removeTenant(string subaccount, string tenant, string actor) {
    auto l = repo.load();
    persist(l, "subaccount:" ~ subaccount.strip, (ref Landscape x) {
      auto s = subaccountRef(x, subaccount.strip);
      auto i = s.tenants.countUntil!(t => t.key == tenant.strip);
      if (i < 0)
        throw new NotFoundException("Tenant", s.key ~ "/" ~ tenant);
      if (s.tenants[i].isDefault)
        throw new ConflictException("The default tenant cannot be removed; make another tenant the default first");
      if (s.tenants[i].sites.length)
        throw new ConflictException("The tenant " ~ tenant ~ " still runs " ~ s.tenants[i].sites.join(", ")
            ~ "; move the sites to another space first");
      s.tenants = s.tenants.remove(i);
      s.modifiedAt = clock.now;
    });
    emit("landscape.tenant.removed", subaccount ~ "/" ~ tenant, actor, "Removed tenant " ~ tenant ~ " of subaccount "
        ~ subaccount);
    return node("subaccount:" ~ subaccount.strip);
  }

  NodeDto saveSpace(string subaccount, string tenant, SpaceRequest r, bool create, string actor) {
    auto l = repo.load();
    auto key = subdomainLabel(r.key);
    auto now = clock.now;
    string[] assigned;
    foreach (site; r.sites) {
      auto k = site.strip.toLower;
      if (k.length == 0 || assigned.canFind(k))
        continue;
      Site existing;
      if (!sites.tryGet(k, existing))
        throw new ValidationException("There is no site '" ~ k ~ "' on this instance");
      assigned ~= k;
    }
    Subaccount target;
    if (!l.trySubaccount(subaccount.strip, target))
      throw new NotFoundException("Subaccount", subaccount);
    if (assigned.length && target.domain != domain)
      throw new ValidationException("Sites of this instance (" ~ domain.label ~ ") can only run in a subaccount of the "
          ~ domain.label ~ " domain");
    persist(l, "subaccount:" ~ target.key, (ref Landscape x) {
      auto s = subaccountRef(x, target.key);
      auto ti = s.tenants.countUntil!(t => t.key == tenant.strip);
      if (ti < 0)
        throw new NotFoundException("Tenant", s.key ~ "/" ~ tenant);
      auto t = &s.tenants[ti];
      auto i = t.spaces.countUntil!(sp => sp.key == key);
      if (create && i >= 0)
        throw new ConflictException("The tenant " ~ t.key ~ " already has a space '" ~ key ~ "'");
      if (!create && i < 0)
        throw new NotFoundException("Space", s.key ~ "/" ~ t.key ~ "/" ~ key);
      Space sp;
      if (create) {
        sp.key = key;
        sp.createdAt = now;
      } else
        sp = t.spaces[i];
      sp.name = requireName(r.name, key);
      sp.description = r.description.strip;
      sp.sites = assigned.sort.array;
      if (i < 0)
        t.spaces ~= sp;
      else
        t.spaces[i] = sp;
      t.modifiedAt = s.modifiedAt = now;
    });
    emit(create ? "landscape.space.created" : "landscape.space.changed", subaccount ~ "/" ~ tenant ~ "/" ~ key, actor,
      (create ? "Created" : "Changed") ~ " space " ~ key ~ " of tenant " ~ tenant ~ " in subaccount " ~ subaccount
        ~ (assigned.length ? " (sites " ~ assigned.join(", ") ~ ")" : ""));
    return node("subaccount:" ~ target.key);
  }

  NodeDto removeSpace(string subaccount, string tenant, string space, string actor) {
    auto l = repo.load();
    persist(l, "subaccount:" ~ subaccount.strip, (ref Landscape x) {
      auto s = subaccountRef(x, subaccount.strip);
      auto ti = s.tenants.countUntil!(t => t.key == tenant.strip);
      if (ti < 0)
        throw new NotFoundException("Tenant", s.key ~ "/" ~ tenant);
      auto t = &s.tenants[ti];
      auto i = t.spaces.countUntil!(sp => sp.key == space.strip);
      if (i < 0)
        throw new NotFoundException("Space", s.key ~ "/" ~ tenant ~ "/" ~ space);
      if (t.spaces[i].isDefault)
        throw new ConflictException("The default space cannot be removed; service calls without a space run there");
      if (t.spaces[i].sites.length)
        throw new ConflictException("The space " ~ space ~ " still runs " ~ t.spaces[i].sites.join(", ")
            ~ "; move the sites first");
      t.spaces = t.spaces.remove(i);
      t.modifiedAt = s.modifiedAt = clock.now;
    });
    emit("landscape.space.removed", subaccount ~ "/" ~ tenant ~ "/" ~ space, actor, "Removed space " ~ space
        ~ " of tenant " ~ tenant ~ " in subaccount " ~ subaccount);
    return node("subaccount:" ~ subaccount.strip);
  }

  // ── billing ─────────────────────────────────────────────────────────────

  BillDto bill(string month = "") {
    auto l = repo.load();
    auto m = monthOrNow(month);
    auto b = computeBill(l, m, usage.ofMonth(m));
    BillDto d;
    d.month = m;
    d.currency = b.currency;
    d.total = b.total;
    d.byPlan = b.byPlan;
    d.unassigned = b.unassigned;
    d.plans = l.plans.dup;
    d.months = usage.months;
    if (!d.months.canFind(m))
      d.months = m ~ d.months;
    foreach (t; tree(l, b, null, null)) {
      BillRowDto row;
      row.node = t.node;
      row.kind = t.kind;
      row.key = t.key;
      row.name = t.name;
      row.level = t.level;
      row.total = t.monthCost;
      if (t.kind == "subaccount")
        foreach (sb; b.subaccounts)
          if (sb.subaccount == t.key) {
            row.costCenter = sb.costCenter;
            row.lines = sb.lines;
            row.requests = sb.requests;
            row.bytesOut = sb.bytesOut;
            row.storageBytes = sb.storageBytes;
            row.sites = sb.sites;
          }
      if (t.kind == "directory") {
        Directory dir;
        if (l.tryDirectory(t.key, dir))
          row.costCenter = dir.costCenter.length ? dir.costCenter : "";
      }
      if (t.kind == "global")
        row.costCenter = l.global.costCenter;
      d.rows ~= row;
    }
    return d;
  }

  string csv(string month = "") {
    auto b = bill(month);
    string text = "month;subaccount;cost_center;plan;quantity;unit;price;amount;currency;entitled;over_quota\n";
    foreach (row; b.rows)
      foreach (line; row.lines)
        text ~= format("%s;%s;%s;%s;%.6f;%s;%.4f;%.4f;%s;%s;%s\n", b.month, row.key, csvText(row.costCenter),
          line.plan, line.quantity, csvText(line.unit), line.price, line.amount, b.currency, line.entitled,
          line.overQuota);
    return text;
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  private string monthOrNow(string month) {
    auto m = month.strip;
    if (m.length == 0)
      return monthOf(clock.now);
    if (m.length != 7 || m[4] != '-')
      throw new ValidationException("Month must look like 2026-11");
    return m;
  }

  /// Apply `mutate` to a copy and refuse it if that adds an error.
  private void change(const Landscape l, scope void delegate(ref Landscape) @safe mutate) {
    auto before = l.validate().filter!(i => i.severity == "error").map!(i => i.node ~ i.message).array;
    auto after = copy(l);
    mutate(after);
    foreach (i; after.validate())
      if (i.severity == "error" && !before.canFind(i.node ~ i.message))
        throw new ValidationException(capitalized(l.label(i.node)) ~ ": " ~ i.message);
  }

  /// Validate, then store the node changed by `mutate`.
  private void persist(const Landscape l, string node, scope void delegate(ref Landscape) @safe mutate) {
    change(l, mutate);
    auto after = copy(l);
    mutate(after);
    if (node == "global")
      repo.saveGlobal(after.global);
    else if (node.length > 10 && node[0 .. 10] == "directory:") {
      Directory d;
      if (!after.tryDirectory(node[10 .. $], d))
        throw new NotFoundException("Directory", node[10 .. $]);
      repo.saveDirectory(d);
    } else if (node.length > 11 && node[0 .. 11] == "subaccount:") {
      Subaccount s;
      if (!after.trySubaccount(node[11 .. $], s))
        throw new NotFoundException("Subaccount", node[11 .. $]);
      repo.saveSubaccount(s);
    } else
      throw new ValidationException("Unknown node '" ~ node ~ "'");
  }

  private NodeDto nodeDto(const Landscape l, string node, const Bill bill) {
    NodeDto d;
    d.node = node;
    auto issues = l.validate();
    auto advice = l.advise();
    d.issues = issues.filter!(i => i.node == node).array;
    d.advice = advice.filter!(a => a.node == node).array;
    auto items = tree(l, bill, issues, advice);
    // children: the items one level below, directly after this node
    auto at = items.countUntil!(t => t.node == node);
    if (at < 0)
      throw new NotFoundException("Node", node);
    d.monthCost = items[at].monthCost;
    foreach (t; items[at + 1 .. $]) {
      if (t.level <= items[at].level)
        break;
      if (t.level == items[at].level + 1)
        d.children ~= t.node;
    }

    if (node == "global") {
      auto g = l.global;
      d.kind = "global";
      d.key = "global";
      d.name = g.name;
      d.subdomainPrefix = g.subdomainPrefix;
      d.subdomainPattern = g.subdomainPattern;
      d.contract = g.contract;
      d.currency = g.currency;
      d.admins = g.admins.dup;
      d.costCenter = d.effectiveCostCenter = g.costCenter;
      d.entitlements = sourceRows(l, node);
      d.roleCollections = g.roleCollections.map!(r => r.copy).array;
      d.modifiedAt = isoTime(g.modifiedAt);
      return d;
    }
    if (node.length > 10 && node[0 .. 10] == "directory:") {
      Directory x;
      if (!l.tryDirectory(node[10 .. $], x))
        throw new NotFoundException("Directory", node[10 .. $]);
      d.kind = "directory";
      d.key = x.key;
      d.name = x.name;
      d.description = x.description;
      d.parent = x.parent;
      d.manageEntitlements = x.manageEntitlements;
      d.manageAuthorizations = x.manageAuthorizations;
      d.owner = x.owner;
      d.depth = l.depth(x.key);
      d.costCenter = x.costCenter;
      d.effectiveCostCenter = x.costCenter.length ? x.costCenter : l.costCenterOf(subaccountIn(x.parent));
      d.entitlementSource = x.manageEntitlements ? l.sourceOf(x) : l.entitlementSource(x.key);
      if (x.manageEntitlements)
        d.entitlements = sourceRows(l, node);
      d.roleCollections = x.roleCollections.map!(r => r.copy).array;
      d.inherited = inherited(l, x.parent);
      d.createdAt = isoTime(x.createdAt);
      d.modifiedAt = isoTime(x.modifiedAt);
      return d;
    }
    if (node.length > 11 && node[0 .. 11] == "subaccount:") {
      Subaccount x;
      if (!l.trySubaccount(node[11 .. $], x))
        throw new NotFoundException("Subaccount", node[11 .. $]);
      d.kind = "subaccount";
      d.key = x.key;
      d.name = x.name;
      d.description = x.description;
      d.directory = x.directory;
      d.region = x.region;
      RegionInfo region;
      d.regionLabel = tryRegion(x.region, region) ? region.provider ~ " · " ~ region.location : x.region;
      d.subdomain = x.subdomain;
      d.purpose = x.purpose;
      d.stage = x.stage.to!string;
      d.domain = x.domain.label;
      d.sites = x.sites;
      d.betaFeatures = x.betaFeatures;
      d.admins = x.admins.dup;
      d.members = x.members.dup;
      d.services = x.services.dup;
      foreach (t; x.tenants)
        d.tenants ~= t.copy;
      d.costCenter = x.costCenter;
      d.effectiveCostCenter = l.costCenterOf(x);
      d.entitlementSource = l.sourceOf(x);
      foreach (e; x.entitlements) {
        ServicePlan p;
        auto known = l.tryPlan(e.plan, p);
        auto row = EntitlementRowDto(e.plan, known ? p.service ~ " · " ~ p.plan : e.plan, known ? p.unit : "", e.quota);
        row.available = e.quota;
        foreach (sb; bill.subaccounts)
          if (sb.subaccount == x.key)
            foreach (line; sb.lines)
              if (line.plan == e.plan && known && p.meter != Meter.none) {
                row.used = line.quantity;
                row.overQuota = line.overQuota;
              }
        d.entitlements ~= row;
      }
      d.roleCollections = x.roleCollections.map!(r => r.copy).array;
      d.inherited = inherited(l, x.directory);
      d.createdAt = isoTime(x.createdAt);
      d.modifiedAt = isoTime(x.modifiedAt);
      return d;
    }
    throw new NotFoundException("Node", node);
  }

  private static EntitlementRowDto[] sourceRows(const Landscape l, string node) {
    EntitlementRowDto[] rows;
    foreach (e; l.entitlementsOf(node)) {
      ServicePlan p;
      auto known = l.tryPlan(e.plan, p);
      bool open;
      auto assigned = l.assignedFrom(node, e.plan, open);
      auto row = EntitlementRowDto(e.plan, known ? p.service ~ " · " ~ p.plan : e.plan, known ? p.unit : "", e.quota,
        assigned, open, e.quota == unlimited ? unlimited : e.quota - assigned);
      row.overQuota = e.quota != unlimited && assigned > e.quota;
      rows ~= row;
    }
    return rows;
  }

  /// Role collections from the global account and the directories above
  /// (those that manage authorizations), nearest last.
  private static InheritedRoleCollectionDto[] inherited(const Landscape l, string directoryKey) {
    InheritedRoleCollectionDto[] result;
    foreach (rc; l.global.roleCollections)
      result ~= InheritedRoleCollectionDto("global", rc.copy);
    auto chain = l.ancestors(directoryKey);
    foreach_reverse (d; chain)
      if (d.manageAuthorizations)
        foreach (rc; d.roleCollections)
          result ~= InheritedRoleCollectionDto("directory:" ~ d.key, rc.copy);
    return result;
  }

  /// The tree in display order: global account, then per level directories
  /// (with their subtrees) and subaccounts.
  private static TreeItemDto[] tree(const Landscape l, const Bill bill, const(LandscapeIssue)[] issues,
      const(Advice)[] advice) {
    TreeItemDto[] items;
    TreeItemDto item(string node, string kind, string key, string name, int level) {
      TreeItemDto t;
      t.node = node;
      t.kind = kind;
      t.key = key;
      t.name = name;
      t.level = level;
      foreach (i; issues)
        if (i.node == node) {
          if (i.severity == "error")
            t.errors++;
          else
            t.warnings++;
        }
      foreach (a; advice)
        if (a.node == node)
          t.advice++;
      return t;
    }

    auto g = item("global", "global", "global", l.global.name, 0);
    g.monthCost = bill.total;
    g.subaccounts = l.subaccounts.length;
    items ~= g;

    void level(string parent, int depth) {
      if (depth > maxDirectoryDepth + 1)
        return;
      foreach (d; l.directories)
        if (d.parent == parent) {
          auto t = item("directory:" ~ d.key, "directory", d.key, d.name, depth);
          t.manageEntitlements = d.manageEntitlements;
          t.manageAuthorizations = d.manageAuthorizations;
          t.subaccounts = l.subaccountsBelow(d.key).length;
          t.monthCost = bill.byDirectory.get(d.key, 0);
          items ~= t;
          level(d.key, depth + 1);
        }
      foreach (s; l.subaccounts)
        if (s.directory == parent) {
          auto t = item("subaccount:" ~ s.key, "subaccount", s.key, s.name, depth);
          t.stage = s.stage.to!string;
          t.region = s.region;
          t.domain = s.domain.label;
          t.subdomain = s.subdomain;
          t.sites = s.sites.length;
          t.tenants = s.tenants.length;
          foreach (sb; bill.subaccounts)
            if (sb.subaccount == s.key)
              t.monthCost = sb.total;
          items ~= t;
        }
    }

    level("", 1);
    return items;
  }

  private static string[] nodes(const Landscape l) {
    string[] result = ["global"];
    foreach (d; l.directories)
      result ~= "directory:" ~ d.key;
    foreach (s; l.subaccounts)
      result ~= "subaccount:" ~ s.key;
    return result;
  }

  private static string features(const Directory d) {
    string[] f;
    if (d.manageEntitlements)
      f ~= "entitlements";
    if (d.manageAuthorizations)
      f ~= "authorizations";
    return f.length ? " (manages " ~ f.join(" and ") ~ ")" : "";
  }

  private void emit(string type, string subject, string actor, string message) {
    invalidate();
    events.publish(PlatformEvent(type, subject, actor, message, clock.now));
  }
}

private void patchEntitlements(ref Landscape x, string node, Entitlement entry, bool remove) {
  void patch(ref Entitlement[] list) {
    auto i = list.countUntil!(e => e.plan == entry.plan);
    if (remove) {
      if (i < 0)
        throw new NotFoundException("Entitlement", entry.plan);
      list = list.remove(i);
    } else if (i < 0)
      list ~= entry;
    else
      list[i] = entry;
  }

  if (node == "global")
    return patch(x.global.entitlements);
  foreach (ref d; x.directories)
    if ("directory:" ~ d.key == node)
      return patch(d.entitlements);
  foreach (ref s; x.subaccounts)
    if ("subaccount:" ~ s.key == node)
      return patch(s.entitlements);
  throw new NotFoundException("Node", node);
}

private void patchCollections(ref Landscape x, string node, RoleCollection rc, bool remove) {
  void patch(ref RoleCollection[] list) {
    auto i = list.countUntil!(e => e.name == rc.name);
    if (remove) {
      if (i < 0)
        throw new NotFoundException("Role collection", rc.name);
      list = list.remove(i);
    } else if (i < 0)
      list ~= rc;
    else
      list[i] = rc;
  }

  if (node == "global")
    return patch(x.global.roleCollections);
  foreach (ref d; x.directories)
    if ("directory:" ~ d.key == node)
      return patch(d.roleCollections);
  foreach (ref s; x.subaccounts)
    if ("subaccount:" ~ s.key == node)
      return patch(s.roleCollections);
  throw new NotFoundException("Node", node);
}

/// The subaccount `key` of `x`, to change in place.
private Subaccount* subaccountRef(return ref Landscape x, string key) @trusted {
  foreach (ref s; x.subaccounts)
    if (s.key == key)
      return &s;
  throw new NotFoundException("Subaccount", key);
}

/// A subaccount placed in `directory` (for inherited values).
private Subaccount subaccountIn(string directory) pure nothrow {
  Subaccount s;
  s.directory = directory;
  return s;
}

/// Valid, unique user names.
private string[] userNames(const(string)[] names) {
  string[] list;
  foreach (n; names)
    if (n.strip.length) {
      auto u = UserName(n).value;
      if (!list.canFind(u))
        list ~= u;
    }
  return list.sort.array;
}

private string requireName(string name, string fallback) {
  auto n = name.strip;
  if (n.length > 128)
    throw new ValidationException("Name exceeds 128 characters");
  return n.length ? n : fallback;
}

private string capitalized(string s) pure {
  import std.ascii : toUpper;

  return s.length ? toUpper(s[0]) ~ s[1 .. $] : s;
}

private string toUpper3(string s) {
  import std.string : toUpper;

  auto c = s.toUpper;
  if (c.length != 3)
    throw new ValidationException("Currency must be a 3-letter code (EUR, USD, CHF)");
  return c;
}

/// "Neko Platform" → "neko-platform"
private string replaceNonLabel(string s) pure {
  import std.ascii : isAlphaNum;

  string r;
  foreach (char c; s)
    r ~= isAlphaNum(c) ? c : '-';
  while (r.canFind("--"))
    r = r.replaceFirst("--", "-");
  while (r.length && r[0] == '-')
    r = r[1 .. $];
  while (r.length && r[$ - 1] == '-')
    r = r[0 .. $ - 1];
  return r.length ? (r.length > 30 ? r[0 .. 30] : r) : "neko";
}

private string replaceFirst(string s, string what, string with_) pure {
  import std.string : indexOf;

  auto i = s.indexOf(what);
  return i < 0 ? s : s[0 .. i] ~ with_ ~ s[i + what.length .. $];
}

private string csvText(string s) pure {
  import std.array : replace;

  return s.replace(";", ",").replace("\n", " ");
}

version (unittest) {
  class FakeLandscape : ILandscapeRepository {
    Landscape data;

    Landscape load() {
      return copy(data);
    }

    void saveGlobal(GlobalAccount g) {
      data.global = g;
    }

    void saveDirectory(Directory d) {
      auto i = data.directories.countUntil!(x => x.key == d.key);
      if (i < 0)
        data.directories ~= d;
      else
        data.directories[i] = d;
    }

    bool removeDirectory(string key) {
      auto before = data.directories.length;
      data.directories = data.directories.filter!(x => x.key != key).array;
      return data.directories.length < before;
    }

    void saveSubaccount(Subaccount s) {
      auto i = data.subaccounts.countUntil!(x => x.key == s.key);
      if (i < 0)
        data.subaccounts ~= s;
      else
        data.subaccounts[i] = s;
    }

    bool removeSubaccount(string key) {
      auto before = data.subaccounts.length;
      data.subaccounts = data.subaccounts.filter!(x => x.key != key).array;
      return data.subaccounts.length < before;
    }

    void savePlan(ServicePlan p) {
      auto i = data.plans.countUntil!(x => x.key == p.key);
      if (i < 0)
        data.plans ~= p;
      else
        data.plans[i] = p;
    }

    bool removePlan(string key) {
      auto before = data.plans.length;
      data.plans = data.plans.filter!(x => x.key != key).array;
      return data.plans.length < before;
    }
  }

  class FakeUsage : IUsageRepository {
    UsageRecord[] items;

    UsageRecord[] ofMonth(string month) {
      return items.filter!(u => u.month == month).array;
    }

    string[] months() {
      return ["2026-11"];
    }

    void add(const(UsageRecord)[] deltas) {
      foreach (d; deltas)
        items ~= UsageRecord(d.month, d.site, d.requests, d.bytesOut, d.peakStorageBytes);
    }
  }
}

///
unittest {
  import std.datetime.date : DateTime;
  import std.datetime.timezone : UTC;
  import std.typecons : nullable;
  import neko.platform.application.services : FixedClock;
  import neko.platform.application.usecases.manage_files : FakeSites;
  import neko.platform.application.usecases.manage_users : fails, NoEvents;

  auto siteRepo = new FakeSites;
  foreach (k; ["main", "shop", "outlet"]) {
    Site s;
    s.key = SiteKey(k);
    siteRepo.save(s);
  }
  auto repo = new FakeLandscape;
  auto usage = new FakeUsage;
  auto uc = new ManageLandscapeUseCase(repo, usage, siteRepo, new NoEvents,
    new FixedClock(SysTime(DateTime(2026, 11, 20, 8, 0, 0), UTC())), SecurityDomain.open);

  uc.ensureDefaults("ACME Platform", "development", "main", ["root"]);
  uc.ensureDefaults("Other", "production", "main"); // only once
  auto start = uc.overview();
  assert(start.month == "2026-11" && start.subaccounts == 1 && start.plans.length == defaultPlans().length);
  auto platform = uc.node("subaccount:platform-open");
  assert(platform.subdomain == "acme-platform-platform-dev" && platform.sites == ["main"] && platform.stage == "dev");
  assert(uc.node("global").name == "ACME Platform" && start.issues.length == 0);

  // a directory with its own budget, below the global account's 10 sites
  DirectoryRequest shop = {key: "shop", name: "Shop", manageEntitlements: true, costCenter: "CC-200", owner: "jane"};
  uc.saveDirectory(shop, true, "admin");
  uc.setEntitlement("directory:shop", "sites.site", 4, false, "admin");
  assert(fails!ValidationException(() { uc.setEntitlement("directory:shop", "sites.site", 6, false, "admin"); }));
  assert(fails!ValidationException(() { uc.setEntitlement("directory:shop", "support.premium", 1, false, "admin"); }));

  SubaccountRequest prod = {key: "shop-prod", name: "Shop production", directory: "shop", region: "eu11",
    purpose: "shop", stage: "prod"};
  auto p = uc.saveSubaccount(prod, true, "admin");
  assert(p.subdomain == "acme-platform-shop-prod" && p.entitlementSource == "directory:shop");
  assert(p.tenants.length == 1 && p.tenants[0].isDefault && p.tenants[0].spaces[0].key == "default");
  // sites run in spaces: two sites but no sites entitlement yet → fine (pay per use) …
  uc.saveSpace("shop-prod", "default", SpaceRequest("default", "Default", "", ["shop", "outlet"]), false, "admin");
  assert(uc.node("subaccount:shop-prod").sites == ["outlet", "shop"]);
  // … but a quota below the number of hosted sites is refused, and so is more than the directory has
  assert(fails!ValidationException(() { uc.setEntitlement("subaccount:shop-prod", "sites.site", 1, false, "admin"); }));
  assert(fails!ValidationException(() { uc.setEntitlement("subaccount:shop-prod", "sites.site", 5, false, "admin"); }));
  uc.setEntitlement("subaccount:shop-prod", "sites.site", 3, false, "admin");
  auto dir = uc.node("directory:shop");
  assert(dir.entitlements[0].assignedBelow == 3 && dir.entitlements[0].available == 1);

  // sites run in one space; region and subdomain are fixed
  SubaccountRequest dev = {key: "shop-dev", name: "Shop dev", directory: "shop", purpose: "shop", stage: "dev"};
  uc.saveSubaccount(dev, true, "admin");
  assert(fails!ValidationException(() {
      uc.saveSpace("shop-dev", "default", SpaceRequest("default", "", "", ["shop"]), false, "admin");
    }));
  assert(fails!ValidationException(() {
      uc.saveSpace("shop-dev", "default", SpaceRequest("default", "", "", ["nowhere"]), false, "admin");
    }));
  prod.region = "eu20";
  assert(fails!InvalidStateTransitionException(() { uc.saveSubaccount(prod, false, "admin"); }));
  prod.region = "";
  prod.domain = "secret";
  assert(fails!ValidationException(() { uc.saveSubaccount(prod, false, "admin"); })); // sites of an open instance
  prod.domain = "";

  // tenants and spaces
  uc.saveTenant("shop-prod", TenantRequest("eu", "Europe"), true, "admin");
  assert(fails!ConflictException(() { uc.saveTenant("shop-prod", TenantRequest("eu"), true, "admin"); }));
  uc.saveSpace("shop-prod", "eu", SpaceRequest("staging", "Staging"), true, "admin");
  auto eu = uc.node("subaccount:shop-prod").tenants[1];
  assert(eu.key == "eu" && !eu.isDefault && eu.spaces.length == 2 && eu.spaces[0].isDefault);
  auto call = uc.resolveCall(CallRequest("eu.acme-platform-shop-prod.example", "", "", "staging"));
  assert(call.subaccount == "shop-prod" && call.tenant == "eu" && call.space == "staging");
  assert(uc.resolveCall(CallRequest("localhost", "", "", "", "outlet")).tenant == "default");
  assert(fails!ConflictException(() { uc.removeSpace("shop-prod", "eu", "default", "admin"); }));
  assert(fails!ConflictException(() { uc.removeTenant("shop-prod", "default", "admin"); }));
  assert(fails!ValidationException(() { uc.saveTenant("shop-prod", TenantRequest("default"), false, "admin"); }));
  uc.saveTenant("shop-prod", TenantRequest("eu", "Europe", "", true), false, "admin"); // eu becomes the default
  assert(uc.resolveCall(CallRequest("acme-platform-shop-prod.example")).tenant == "eu");
  uc.saveTenant("shop-prod", TenantRequest("default", "Default", "", true), false, "admin");
  uc.removeSpace("shop-prod", "eu", "staging", "admin");
  uc.removeTenant("shop-prod", "eu", "admin");
  assert(uc.node("subaccount:shop-prod").tenants.length == 1);
  assert(fails!NotFoundException(() { uc.removeTenant("shop-prod", "nope", "admin"); }));

  // administrators, user group, services
  uc.setSubaccountAccess("shop-prod", SubaccountAccessRequest(["Ann"], ["bob", "ann"], ["sites", "files"]), "admin");
  auto access = uc.node("subaccount:shop-prod");
  assert(access.admins == ["ann"] && access.members == ["bob"] && access.services == ["files", "sites"]);
  assert(uc.mayAdminister("shop-prod", "ann") && !uc.mayAdminister("shop-dev", "ann"));
  assert(uc.grantedRights("bob") == ["landscape.read"] && uc.grantedRights("eve").length == 0);
  assert(uc.mayAdminister("shop-dev", "root") && uc.grantedRights("root").length == 3);
  assert(fails!ValidationException(() {
      uc.setSubaccountAccess("shop-prod", SubaccountAccessRequest(null, null, ["nosuch"]), "admin");
    }));
  uc.saveRoleCollection("subaccount:shop-prod", RoleCollectionRequest("Editors", "", ["sites.manage"], ["bob"]),
    "ann");
  // not in the user group / a service not selected / dropping a member still in a role collection
  assert(fails!ValidationException(() {
      uc.saveRoleCollection("subaccount:shop-prod", RoleCollectionRequest("X", "", ["sites.read"], ["eve"]), "ann");
    }));
  assert(fails!ValidationException(() {
      uc.saveRoleCollection("subaccount:shop-prod", RoleCollectionRequest("X", "", ["users.read"], ["bob"]), "ann");
    }));
  assert(fails!ValidationException(() {
      uc.setSubaccountAccess("shop-prod", SubaccountAccessRequest(["ann"], null, ["sites", "files"]), "ann");
    }));
  uc.removeRoleCollection("subaccount:shop-prod", "Editors", "ann");

  // role collections: directories only with authorizations enabled
  auto admins = RoleCollectionRequest("Shop Admin", "", ["sites.manage", "files.manage"], ["Jane", "jane"]);
  assert(fails!ValidationException(() { uc.saveRoleCollection("directory:shop", admins, "admin"); }));
  shop.manageAuthorizations = true;
  uc.saveDirectory(shop, false, "admin");
  assert(uc.saveRoleCollection("directory:shop", admins, "admin").roleCollections[0].members == ["jane"]);
  auto inherited = uc.node("subaccount:shop-dev").inherited;
  assert(inherited.length == 1 && inherited[0].origin == "directory:shop");
  // prod and dev below one directory with a changing role collection: advice
  assert(uc.overview().advice.any!(a => a.node == "directory:shop" && a.topic == "authorizations"));
  assert(fails!ValidationException(() {
      uc.saveRoleCollection("subaccount:shop-dev", RoleCollectionRequest("x", "", ["no.such"]), "admin");
    }));

  // billing: usage of the shop sites goes to shop-prod and up to the directory
  enum gib = 1024L * 1024 * 1024;
  usage.add([UsageRecord("2026-11", "shop", 100_000, 2 * gib, gib), UsageRecord("2026-11", "nowhere", 7, 0, 0)]);
  auto bill = uc.bill();
  auto row = bill.rows.filter!(r => r.node == "subaccount:shop-prod").front;
  assert(row.requests == 100_000 && row.costCenter == "CC-200" && row.total > 0);
  assert(bill.rows.filter!(r => r.node == "directory:shop").front.total == row.total);
  assert(bill.rows[0].node == "global" && bill.unassigned.length == 1);
  assert(uc.csv().canFind("shop-prod;CC-200;platform.requests;100.000000"));

  // removal rules
  assert(fails!ConflictException(() { uc.removeDirectory("shop", "admin"); }));
  assert(fails!ConflictException(() { uc.removeSubaccount("shop-prod", "admin"); }));
  assert(fails!ConflictException(() { uc.removePlan("sites.site", "admin"); }));
  uc.removeSubaccount("shop-dev", "admin");
  assert(uc.overview().subaccounts == 2);
}
