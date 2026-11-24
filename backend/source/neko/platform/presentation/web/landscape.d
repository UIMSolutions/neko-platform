/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The account hierarchy, billing, service assignments and disaster
/// recovery (web interface; htmx fragments).
///
///   GET  /landscape?node=&month=               tree, node details, recommendations   landscape.read
///   GET  /landscape/global/edit, POST /landscape/global                              landscape.manage
///   GET  /landscape/directories/new?parent=, POST /landscape/directories             landscape.manage
///   GET  /landscape/directories/:key/edit, POST /landscape/directories/:key[/delete] landscape.manage
///   GET  /landscape/subaccounts/new?directory=, POST /landscape/subaccounts          landscape.manage
///   GET  /landscape/subaccounts/:key/edit, POST /landscape/subaccounts/:key[/delete] landscape.manage
///   GET  /landscape/entitlement?node=&plan=, POST /landscape/entitlement[/delete]    landscape.manage
///   GET  /landscape/rolecollection?node=&name=, POST /landscape/rolecollection[/delete]  landscape.manage (*)
///   GET  /landscape/subaccounts/:key/access, POST                                  (*)
///   GET  /landscape/subaccounts/:key/tenants/new, …/tenants/:tenant/edit           (*)
///   POST /landscape/subaccounts/:key/tenants, …/tenants/:tenant[/delete]           (*)
///   GET  …/tenants/:tenant/spaces/new, …/spaces/:space/edit                         (*)
///   POST …/tenants/:tenant/spaces, …/spaces/:space[/delete]                         (*)
///   (*) landscape.manage, or administrator of the subaccount (landscape.read)
///   GET  /landscape/billing?month=, GET /landscape/billing.csv?month=                billing.read
///   GET  /landscape/plans/new, /landscape/plans/:key/edit, POST /landscape/plans[/:key/delete]  landscape.manage
///   GET  /landscape/assignments                    services × subaccounts, entitlements   landscape.read
///   POST /landscape/assignments                    (un)assign a service: service=, subaccount=…, assign=1|0
///                                                                                          landscape.manage
///   GET  /landscape/recovery                       disaster recovery of every subaccount  landscape.read
///   GET  /landscape/recovery/:key/plan, POST       recovery plan                          (*)
///   GET  /landscape/recovery/:key/failover|failback|drill, POST                           (*)
module neko.platform.presentation.web.landscape;

import std.algorithm : canFind, map, splitter;
import std.array : array;
import std.conv : to;
import std.string : strip;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos;
import neko.platform.domain : PlatformException;
import neko.platform.domain.entities.landscape : RegionInfo, regions, RoleCollection, ServicePlan, unlimited;
import neko.platform.ports.usecases : IBillingUseCase, IManageLandscapeUseCase, IManageRolesUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.support;

@safe:

struct GlobalForm {
  GlobalAccountRequest values;
  string error;
}

struct DirectoryForm {
  bool existing;
  DirectoryRequest values;
  string error;
}

struct SubaccountForm {
  bool existing;
  SubaccountRequest values;
  /// The subdomain the scheme would give (shown as placeholder).
  string schemeHint;
  string error;
}

struct EntitlementForm {
  string node;
  string nodeLabel;
  string plan;
  long quota;
  bool unlimited_;
  bool existing;
  string error;
}

struct RoleCollectionForm {
  string node;
  string nodeLabel;
  bool existing;
  RoleCollectionRequest values;
  string error;
}

struct AccessForm {
  string subaccount;
  SubaccountAccessRequest values;
  string error;
}

struct TenantForm {
  string subaccount;
  bool existing;
  TenantRequest values;
  string error;
}

struct SpaceForm {
  string subaccount;
  string tenant;
  bool existing;
  SpaceRequest values;
  string error;
}

struct PlanForm {
  bool existing;
  ServicePlanRequest values;
  string error;
}

struct RecoveryPlanForm {
  RecoveryDto current;
  RecoveryPlanRequest values;
  string error;
}

/// A failover, failback or drill.
struct RecoveryActionForm {
  RecoveryDto current;
  /// "failover" | "failback" | "drill"
  string action;
  string reason;
  long minutes;
  bool worked = true;
  string error;
}

@requiresAuth
class LandscapeWeb {
  private WebGuard guard;
  private IManageLandscapeUseCase landscape;
  private IBillingUseCase billing;

  mixin PageAuthentication;

  this(WebGuard guard, IManageLandscapeUseCase landscape, IBillingUseCase billing) {
    this.guard = guard;
    this.landscape = landscape;
    this.billing = billing;
  }

  @auth(Role.landscapeRead) @path("/landscape")
  void getLandscape(PageContext page, HTTPServerResponse res, string node = "global", string month = "") {
    page = page.at("Landscape", "landscape");
    auto view = landscape.overview(month);
    NodeDto selected;
    try
      selected = landscape.node(node, month);
    catch (PlatformException)
      selected = landscape.node("global", month);
    page.mayAdministerNode = mayAdminister(page, selected.node);
    render!("landscape.dt", page, view, selected);
  }

  // ── global account ──────────────────────────────────────────────────────

  @auth(Role.landscapeManage) @path("/landscape/global/edit")
  void getGlobal(PageContext page) {
    auto g = landscape.node("global");
    auto form = GlobalForm(GlobalAccountRequest(g.name, g.subdomainPrefix, g.subdomainPattern, g.contract, g.currency,
      g.costCenter, g.admins));
    render!("landscape_global_dialog.dt", page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/global")
  void postGlobal(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = GlobalForm(GlobalAccountRequest(req.form.get("name", ""), req.form.get("subdomainPrefix", ""),
      req.form.get("subdomainPattern", ""), req.form.get("contract", ""), req.form.get("currency", ""),
      req.form.get("costCenter", ""), words(req.form.get("admins", ""))));
    try {
      landscape.updateGlobal(form.values, page.user.userName);
      refresh(res, page, "global", "Global account saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("landscape_global_dialog.dt", page, form);
    }
  }

  // ── directories ─────────────────────────────────────────────────────────

  @auth(Role.landscapeManage) @path("/landscape/directories/new")
  void getNewDirectory(PageContext page, string parent = "") {
    DirectoryForm form;
    form.values.parent = parent;
    directoryDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/directories")
  void postDirectories(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    saveDirectory(page, req, res, false, req.form.get("key", ""));
  }

  @auth(Role.landscapeManage) @path("/landscape/directories/:key/edit")
  void getEditDirectory(PageContext page, HTTPServerResponse res, string _key) {
    NodeDto d;
    if (!load(res, page, "directory:" ~ _key, d))
      return;
    auto form = DirectoryForm(true, DirectoryRequest(d.key, d.name, d.description, d.parent, d.manageEntitlements,
      d.manageAuthorizations, d.costCenter, d.owner));
    directoryDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/directories/:key")
  void postDirectory(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    saveDirectory(page, req, res, true, _key);
  }

  @auth(Role.landscapeManage) @path("/landscape/directories/:key/delete")
  void postDeleteDirectory(PageContext page, HTTPServerResponse res, string _key) {
    try {
      landscape.removeDirectory(_key, page.user.userName);
      refresh(res, page, "global", "Directory " ~ _key ~ " removed", false);
    } catch (PlatformException e)
      refresh(res, page, "directory:" ~ _key, e.msg, true);
  }

  @noRoute void saveDirectory(PageContext page, HTTPServerRequest req, HTTPServerResponse res, bool existing,
      string key) {
    auto form = DirectoryForm(existing, DirectoryRequest(key, req.form.get("name", ""), req.form.get("description", ""),
      req.form.get("parent", ""), req.form.get("manageEntitlements", "") == "on",
      req.form.get("manageAuthorizations", "") == "on", req.form.get("costCenter", ""), req.form.get("owner", "")));
    try {
      auto d = landscape.saveDirectory(form.values, !existing, page.user.userName);
      refresh(res, page, d.node, "Directory " ~ d.key ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      directoryDialog(page, form);
    }
  }

  @noRoute void directoryDialog(PageContext page, DirectoryForm form) {
    auto view = landscape.overview();
    render!("landscape_directory_dialog.dt", page, form, view);
  }

  // ── subaccounts ─────────────────────────────────────────────────────────

  @auth(Role.landscapeManage) @path("/landscape/subaccounts/new")
  void getNewSubaccount(PageContext page, string directory = "") {
    SubaccountForm form;
    form.values.directory = directory;
    form.values.domain = page.domain;
    subaccountDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/subaccounts")
  void postSubaccounts(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    saveSubaccount(page, req, res, false, req.form.get("key", ""));
  }

  @auth(Role.landscapeManage) @path("/landscape/subaccounts/:key/edit")
  void getEditSubaccount(PageContext page, HTTPServerResponse res, string _key) {
    NodeDto s;
    if (!load(res, page, "subaccount:" ~ _key, s))
      return;
    auto form = SubaccountForm(true, SubaccountRequest(s.key, s.name, s.description, s.directory, s.region,
      s.subdomain, s.purpose, s.stage, s.domain, s.costCenter, s.betaFeatures));
    subaccountDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/subaccounts/:key")
  void postSubaccount(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    saveSubaccount(page, req, res, true, _key);
  }

  @auth(Role.landscapeManage) @path("/landscape/subaccounts/:key/delete")
  void postDeleteSubaccount(PageContext page, HTTPServerResponse res, string _key) {
    try {
      landscape.removeSubaccount(_key, page.user.userName);
      refresh(res, page, "global", "Subaccount " ~ _key ~ " removed", false);
    } catch (PlatformException e)
      refresh(res, page, "subaccount:" ~ _key, e.msg, true);
  }

  @noRoute void saveSubaccount(PageContext page, HTTPServerRequest req, HTTPServerResponse res, bool existing,
      string key) {
    auto form = SubaccountForm(existing, SubaccountRequest(key, req.form.get("name", ""),
      req.form.get("description", ""), req.form.get("directory", ""), req.form.get("region", ""),
      req.form.get("subdomain", ""), req.form.get("purpose", ""), req.form.get("stage", "dev"),
      req.form.get("domain", ""), req.form.get("costCenter", ""),
      req.form.get("betaFeatures", "") == "on"));
    try {
      auto s = landscape.saveSubaccount(form.values, !existing, page.user.userName);
      refresh(res, page, s.node, "Subaccount " ~ s.key ~ " saved (" ~ s.subdomain ~ ")", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      subaccountDialog(page, form);
    }
  }

  @noRoute void subaccountDialog(PageContext page, SubaccountForm form) {
    auto view = landscape.overview();
    auto g = landscape.node("global");
    form.schemeHint = g.subdomainPattern.length ? g.subdomainPattern : "";
    auto regionList = regions.dup;
    render!("landscape_subaccount_dialog.dt", page, form, view, g, regionList);
  }

  // ── subaccount access: administrators, user group, services ─────────────

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/access")
  void getAccess(PageContext page, HTTPServerResponse res, string _key) {
    NodeDto s;
    if (!load(res, page, "subaccount:" ~ _key, s) || !allowed(res, page, s.node))
      return;
    auto form = AccessForm(s.key, SubaccountAccessRequest(s.admins, s.members, s.services));
    accessDialog(page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/access")
  void postAccess(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    if (!allowed(res, page, "subaccount:" ~ _key))
      return;
    auto form = AccessForm(_key, SubaccountAccessRequest(words(req.form.get("admins", "")),
      words(req.form.get("members", "")), req.form.getAll("services").dup));
    try {
      landscape.setSubaccountAccess(_key, form.values, page.user.userName);
      refresh(res, page, "subaccount:" ~ _key, "Administrators, user group and services of " ~ _key ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      accessDialog(page, form);
    }
  }

  @noRoute void accessDialog(PageContext page, AccessForm form) {
    import neko.platform.domain.entities.landscape : serviceCatalogue;

    auto catalogue = serviceCatalogue();
    render!("landscape_access_dialog.dt", page, form, catalogue);
  }

  // ── tenants ─────────────────────────────────────────────────────────────

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/new")
  void getNewTenant(PageContext page, HTTPServerResponse res, string _key) {
    if (!allowed(res, page, "subaccount:" ~ _key))
      return;
    TenantForm form;
    form.subaccount = _key;
    render!("landscape_tenant_dialog.dt", page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/edit")
  void getEditTenant(PageContext page, HTTPServerResponse res, string _key, string _tenant) {
    NodeDto s;
    if (!load(res, page, "subaccount:" ~ _key, s) || !allowed(res, page, s.node))
      return;
    foreach (t; s.tenants)
      if (t.key == _tenant) {
        auto form = TenantForm(_key, true, TenantRequest(t.key, t.name, t.description, t.isDefault));
        return render!("landscape_tenant_dialog.dt", page, form);
      }
    res.writeBody("There is no tenant " ~ _tenant, 404, "text/plain; charset=utf-8");
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants")
  void postTenants(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    saveTenant(page, req, res, _key, false, req.form.get("key", ""));
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant")
  void postTenant(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key, string _tenant) {
    saveTenant(page, req, res, _key, true, _tenant);
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/delete")
  void postDeleteTenant(PageContext page, HTTPServerResponse res, string _key, string _tenant) {
    if (!allowed(res, page, "subaccount:" ~ _key))
      return;
    try {
      landscape.removeTenant(_key, _tenant, page.user.userName);
      refresh(res, page, "subaccount:" ~ _key, "Tenant " ~ _tenant ~ " removed", false);
    } catch (PlatformException e)
      refresh(res, page, "subaccount:" ~ _key, e.msg, true);
  }

  @noRoute void saveTenant(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string subaccount,
      bool existing, string key) {
    if (!allowed(res, page, "subaccount:" ~ subaccount))
      return;
    auto form = TenantForm(subaccount, existing, TenantRequest(key, req.form.get("name", ""),
      req.form.get("description", ""), req.form.get("isDefault", "") == "on"));
    try {
      landscape.saveTenant(subaccount, form.values, !existing, page.user.userName);
      refresh(res, page, "subaccount:" ~ subaccount, "Tenant " ~ key.strip ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("landscape_tenant_dialog.dt", page, form);
    }
  }

  // ── spaces ──────────────────────────────────────────────────────────────

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/spaces/new")
  void getNewSpace(PageContext page, HTTPServerResponse res, string _key, string _tenant) {
    if (!allowed(res, page, "subaccount:" ~ _key))
      return;
    SpaceForm form;
    form.subaccount = _key;
    form.tenant = _tenant;
    spaceDialog(page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/spaces/:space/edit")
  void getEditSpace(PageContext page, HTTPServerResponse res, string _key, string _tenant, string _space) {
    NodeDto s;
    if (!load(res, page, "subaccount:" ~ _key, s) || !allowed(res, page, s.node))
      return;
    foreach (t; s.tenants)
      if (t.key == _tenant)
        foreach (sp; t.spaces)
          if (sp.key == _space) {
            auto form = SpaceForm(_key, _tenant, true, SpaceRequest(sp.key, sp.name, sp.description));
            return spaceDialog(page, form);
          }
    res.writeBody("There is no space " ~ _tenant ~ "/" ~ _space, 404, "text/plain; charset=utf-8");
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/spaces")
  void postSpaces(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key, string _tenant) {
    saveSpace(page, req, res, _key, _tenant, false, req.form.get("key", ""));
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/spaces/:space")
  void postSpace(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key, string _tenant,
      string _space) {
    saveSpace(page, req, res, _key, _tenant, true, _space);
  }

  @auth(Role.landscapeRead) @path("/landscape/subaccounts/:key/tenants/:tenant/spaces/:space/delete")
  void postDeleteSpace(PageContext page, HTTPServerResponse res, string _key, string _tenant, string _space) {
    if (!allowed(res, page, "subaccount:" ~ _key))
      return;
    try {
      landscape.removeSpace(_key, _tenant, _space, page.user.userName);
      refresh(res, page, "subaccount:" ~ _key, "Space " ~ _tenant ~ "/" ~ _space ~ " removed", false);
    } catch (PlatformException e)
      refresh(res, page, "subaccount:" ~ _key, e.msg, true);
  }

  @noRoute void saveSpace(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string subaccount,
      string tenant, bool existing, string key) {
    if (!allowed(res, page, "subaccount:" ~ subaccount))
      return;
    auto form = SpaceForm(subaccount, tenant, existing, SpaceRequest(key, req.form.get("name", ""),
      req.form.get("description", "")));
    try {
      landscape.saveSpace(subaccount, tenant, form.values, !existing, page.user.userName);
      refresh(res, page, "subaccount:" ~ subaccount, "Space " ~ tenant ~ "/" ~ key.strip ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      spaceDialog(page, form);
    }
  }

  @noRoute void spaceDialog(PageContext page, SpaceForm form) {
    render!("landscape_space_dialog.dt", page, form);
  }

  // ── entitlements ────────────────────────────────────────────────────────

  @auth(Role.landscapeManage) @path("/landscape/entitlement")
  void getEntitlement(PageContext page, HTTPServerResponse res, string node, string plan = "") {
    NodeDto n;
    if (!load(res, page, node, n))
      return;
    auto form = EntitlementForm(node, label(n), plan, 1);
    foreach (e; n.entitlements)
      if (e.plan == plan) {
        form.existing = true;
        form.quota = e.quota == unlimited ? 0 : e.quota;
        form.unlimited_ = e.quota == unlimited;
      }
    entitlementDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/entitlement")
  void postEntitlement(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = EntitlementForm(req.form.get("node", ""), "", req.form.get("plan", ""), 0,
      req.form.get("unlimited", "") == "on", req.form.get("existing", "") == "1");
    try {
      form.quota = req.form.get("quota", "0").strip.to!long;
    } catch (Exception) {
      form.error = "The quota must be a whole number";
    }
    if (form.error.length == 0)
      try {
        landscape.setEntitlement(form.node, form.plan, form.unlimited_ ? unlimited : form.quota, false,
          page.user.userName);
        return refresh(res, page, form.node, form.plan ~ " entitled", false);
      } catch (PlatformException e)
        form.error = e.msg;
    try
      form.nodeLabel = label(landscape.node(form.node));
    catch (PlatformException) {
    }
    entitlementDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/entitlement/delete")
  void postDeleteEntitlement(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto node = req.form.get("node", ""), plan = req.form.get("plan", "");
    try {
      landscape.setEntitlement(node, plan, 0, true, page.user.userName);
      refresh(res, page, node, plan ~ " removed", false);
    } catch (PlatformException e)
      refresh(res, page, node, e.msg, true);
  }

  @noRoute void entitlementDialog(PageContext page, EntitlementForm form) {
    auto plans = landscape.plans();
    render!("landscape_entitlement_dialog.dt", page, form, plans);
  }

  // ── role collections ────────────────────────────────────────────────────

  @auth(Role.landscapeRead) @path("/landscape/rolecollection")
  void getRoleCollection(PageContext page, HTTPServerResponse res, string node, string name = "") {
    NodeDto n;
    if (!load(res, page, node, n) || !allowed(res, page, node))
      return;
    auto form = RoleCollectionForm(node, label(n));
    foreach (rc; n.roleCollections)
      if (rc.name == name) {
        form.existing = true;
        form.values = RoleCollectionRequest(rc.name, rc.description, rc.rights.dup, rc.members.dup);
      }
    roleCollectionDialog(page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/rolecollection")
  void postRoleCollection(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    if (!allowed(res, page, req.form.get("node", "")))
      return;
    auto form = RoleCollectionForm(req.form.get("node", ""), "", req.form.get("existing", "") == "1",
      RoleCollectionRequest(req.form.get("name", ""), req.form.get("description", ""), req.form.getAll("rights").dup,
      words(req.form.get("members", ""))));
    try {
      landscape.saveRoleCollection(form.node, form.values, page.user.userName);
      return refresh(res, page, form.node, "Role collection " ~ form.values.name.strip ~ " saved", false);
    } catch (PlatformException e)
      form.error = e.msg;
    try
      form.nodeLabel = label(landscape.node(form.node));
    catch (PlatformException) {
    }
    roleCollectionDialog(page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/rolecollection/delete")
  void postDeleteRoleCollection(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto node = req.form.get("node", ""), name = req.form.get("name", "");
    if (!allowed(res, page, node))
      return;
    try {
      landscape.removeRoleCollection(node, name, page.user.userName);
      refresh(res, page, node, "Role collection " ~ name ~ " removed", false);
    } catch (PlatformException e)
      refresh(res, page, node, e.msg, true);
  }

  @noRoute void roleCollectionDialog(PageContext page, RoleCollectionForm form) {
    import neko.platform.domain.enumerations.rights : accessRights;

    auto catalogue = accessRights.dup;
    render!("landscape_rolecollection_dialog.dt", page, form, catalogue);
  }

  // ── billing and service plans ───────────────────────────────────────────

  @auth(Role.billingRead) @path("/landscape/billing")
  void getBilling(PageContext page, string month = "") {
    page = page.at("Billing", "landscape");
    BillDto bill;
    string error;
    try
      bill = billing.bill(month);
    catch (PlatformException e) {
      error = e.msg;
      bill = billing.bill();
    }
    render!("billing.dt", page, bill, error);
  }

  @auth(Role.billingRead) @path("/landscape/billing.csv")
  void getBillingCsv(PageContext page, HTTPServerResponse res, string month = "") {
    auto text = billing.csv(month);
    auto name = "billing-" ~ (month.length ? month : billing.bill().month) ~ ".csv";
    res.headers["Content-Disposition"] = `attachment; filename="` ~ asciiOnly(name) ~ `"`;
    res.writeBody(text, "text/csv; charset=utf-8");
  }

  @auth(Role.landscapeManage) @path("/landscape/plans/new")
  void getNewPlan(PageContext page) {
    PlanForm form;
    render!("landscape_plan_dialog.dt", page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/plans/:key/edit")
  void getEditPlan(PageContext page, HTTPServerResponse res, string _key) {
    foreach (p; landscape.plans())
      if (p.key == _key) {
        auto form = PlanForm(true, ServicePlanRequest(p.key, p.service, p.plan, p.description, p.unit, p.unitSize,
          p.price, p.meter.to!string));
        return render!("landscape_plan_dialog.dt", page, form);
      }
    res.writeBody("There is no service plan " ~ _key, 404, "text/plain; charset=utf-8");
  }

  @auth(Role.landscapeManage) @path("/landscape/plans")
  void postPlans(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = PlanForm(req.form.get("existing", "") == "1", ServicePlanRequest(req.form.get("key", ""),
      req.form.get("service", ""), req.form.get("plan", ""), req.form.get("description", ""), req.form.get("unit", ""),
      0, 0, req.form.get("meter", "none")));
    try {
      form.values.unitSize = req.form.get("unitSize", "1").strip.to!double;
      form.values.price = req.form.get("price", "0").strip.to!double;
    } catch (Exception) {
      form.error = "Unit size and price must be numbers (e.g. 1073741824, 0.025)";
      return render!("landscape_plan_dialog.dt", page, form);
    }
    try {
      auto p = landscape.savePlan(form.values, page.user.userName);
      plansTable(res, page, "Service plan " ~ p.key ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("landscape_plan_dialog.dt", page, form);
    }
  }

  @auth(Role.landscapeManage) @path("/landscape/plans/:key/delete")
  void postDeletePlan(PageContext page, HTTPServerResponse res, string _key) {
    try {
      landscape.removePlan(_key, page.user.userName);
      plansTable(res, page, "Service plan " ~ _key ~ " removed", false);
    } catch (PlatformException e)
      plansTable(res, page, e.msg, true);
  }

  @noRoute void plansTable(HTTPServerResponse res, PageContext page, string message, bool error) {
    swapTable(res, "plans", message, error);
    auto bill = billing.bill();
    render!("billing_plans.dt", page, bill);
  }

  // ── service assignments ─────────────────────────────────────────────────

  @auth(Role.landscapeRead) @path("/landscape/assignments")
  void getAssignments(PageContext page) {
    page = page.at("Service assignments", "landscape");
    auto view = landscape.serviceAssignments();
    render!("assignments.dt", page, view);
  }

  /// One cell (subaccount=<key>) or a whole row (subaccount=<key>,<key>,…).
  @auth(Role.landscapeManage) @path("/landscape/assignments")
  void postAssignments(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    string[] keys;
    foreach (field; req.form.getAll("subaccount"))
      keys ~= words(field);
    auto r = ServiceAssignmentRequest(req.form.get("service", ""), keys, req.form.get("assign", "1") == "1");
    string message;
    bool error;
    try {
      landscape.assignService(r, page.user.userName);
      message = (r.assign ? "Assigned " : "Unassigned ") ~ r.service ~ (r.assign ? " to " : " from ")
        ~ (r.subaccounts.length == 1 ? r.subaccounts[0] : r.subaccounts.length.to!string ~ " subaccounts");
    } catch (PlatformException e) {
      message = e.msg;
      error = true;
    }
    swapTable(res, "assignments", message, error);
    auto view = landscape.serviceAssignments();
    render!("assignments_table.dt", page, view);
  }

  // ── disaster recovery ───────────────────────────────────────────────────

  @auth(Role.landscapeRead) @path("/landscape/recovery")
  void getRecovery(PageContext page) {
    page = page.at("Disaster recovery", "landscape");
    auto view = landscape.recoveryOverview();
    auto adminOf = administered(page, view);
    render!("recovery.dt", page, view, adminOf);
  }

  @auth(Role.landscapeRead) @path("/landscape/recovery/:key/plan")
  void getRecoveryPlan(PageContext page, HTTPServerResponse res, string _key) {
    RecoveryDto current;
    if (!loadRecovery(res, page, _key, current))
      return;
    auto form = RecoveryPlanForm(current, RecoveryPlanRequest(current.enabled || current.secondaryRegion.length == 0,
      current.secondaryRegion, current.strategy, current.rpoMinutes, current.rtoMinutes));
    recoveryPlanDialog(page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/recovery/:key/plan")
  void postRecoveryPlan(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    RecoveryDto current;
    if (!loadRecovery(res, page, _key, current))
      return;
    auto form = RecoveryPlanForm(current, RecoveryPlanRequest(req.form.get("enabled", "") == "on",
      req.form.get("secondaryRegion", ""), req.form.get("strategy", "")));
    try {
      form.values.rpoMinutes = req.form.get("rpoMinutes", "0").strip.to!long;
      form.values.rtoMinutes = req.form.get("rtoMinutes", "0").strip.to!long;
    } catch (Exception) {
      form.error = "RPO and RTO must be whole numbers of minutes";
      return recoveryPlanDialog(page, form);
    }
    try {
      auto d = landscape.configureRecovery(_key, form.values, page.user.userName);
      recoveryTable(res, page, "Disaster recovery of " ~ d.subaccount ~ (d.enabled ? " saved (" ~ d.status ~ ")"
          : " disabled"), false);
    } catch (PlatformException e) {
      form.error = e.msg;
      recoveryPlanDialog(page, form);
    }
  }

  @auth(Role.landscapeRead) @path("/landscape/recovery/:key/:action")
  void getRecoveryAction(PageContext page, HTTPServerResponse res, string _key, string _action) {
    RecoveryDto current;
    if (!knownAction(res, _action) || !loadRecovery(res, page, _key, current))
      return;
    auto form = RecoveryActionForm(current, _action);
    if (_action == "drill")
      form.minutes = current.rtoMinutes;
    render!("recovery_action_dialog.dt", page, form);
  }

  @auth(Role.landscapeRead) @path("/landscape/recovery/:key/:action")
  void postRecoveryAction(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key,
      string _action) {
    RecoveryDto current;
    if (!knownAction(res, _action) || !loadRecovery(res, page, _key, current))
      return;
    auto form = RecoveryActionForm(current, _action, req.form.get("reason", ""), 0,
      req.form.get("worked", "") == "on");
    try
      form.minutes = req.form.get("minutes", "0").strip.length ? req.form.get("minutes", "0").strip.to!long : 0;
    catch (Exception) {
      form.error = "The duration must be a whole number of minutes";
      return render!("recovery_action_dialog.dt", page, form);
    }
    try {
      RecoveryDto d;
      string message;
      switch (_action) {
      case "failover":
        d = landscape.failover(_key, RecoveryActionRequest(form.reason, form.minutes), page.user.userName);
        message = d.subaccount ~ " now runs in " ~ d.activeRegion;
        break;
      case "failback":
        d = landscape.failback(_key, RecoveryActionRequest(form.reason, form.minutes), page.user.userName);
        message = d.subaccount ~ " is back in " ~ d.activeRegion;
        break;
      default:
        d = landscape.recordDrill(_key, RecoveryDrillRequest(form.minutes, form.worked, form.reason),
          page.user.userName);
        message = "Drill of " ~ d.subaccount ~ (d.history[0].success ? " passed" : " failed");
      }
      recoveryTable(res, page, message, d.history.length && !d.history[0].success);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("recovery_action_dialog.dt", page, form);
    }
  }

  @noRoute void recoveryPlanDialog(PageContext page, RecoveryPlanForm form) {
    auto view = landscape.recoveryOverview();
    render!("recovery_plan_dialog.dt", page, form, view);
  }

  /// The refreshed recovery table, a toast and "close dialog".
  @noRoute void recoveryTable(HTTPServerResponse res, PageContext page, string message, bool error) {
    swapTable(res, "recovery", message, error);
    auto view = landscape.recoveryOverview();
    auto adminOf = administered(page, view);
    render!("recovery_table.dt", page, view, adminOf);
  }

  /// The subaccounts whose recovery `page.user` may change.
  @noRoute bool[string] administered(const PageContext page, const RecoveryOverviewDto view) {
    bool[string] map;
    foreach (s; view.subaccounts)
      map[s.subaccount] = mayAdminister(page, "subaccount:" ~ s.subaccount);
    return map;
  }

  /// The recovery of `key` if the user may change it (else answers 404 or 403).
  @noRoute bool loadRecovery(HTTPServerResponse res, PageContext page, string key, out RecoveryDto d) {
    try
      d = landscape.recovery(key);
    catch (PlatformException e) {
      res.writeBody(e.msg, 404, "text/plain; charset=utf-8");
      return false;
    }
    return allowed(res, page, "subaccount:" ~ d.subaccount);
  }

  @noRoute static bool knownAction(HTTPServerResponse res, string action) {
    if (action == "failover" || action == "failback" || action == "drill")
      return true;
    res.writeBody("Unknown action " ~ action, 404, "text/plain; charset=utf-8");
    return false;
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  /// The refreshed hierarchy with `node` selected, a toast, "close dialog".
  @noRoute void refresh(HTTPServerResponse res, PageContext page, string node, string message, bool error) {
    swapTable(res, "landscape", message, error);
    auto view = landscape.overview();
    NodeDto selected;
    try
      selected = landscape.node(node);
    catch (PlatformException)
      selected = landscape.node("global");
    page.mayAdministerNode = mayAdminister(page, selected.node);
    render!("landscape_body.dt", page, view, selected);
  }

  /// landscape.manage, or an administrator of the subaccount `node`.
  @noRoute bool mayAdminister(const PageContext page, string node) {
    if (page.isLandscapeManage)
      return true;
    return node.length > 11 && node[0 .. 11] == "subaccount:" && landscape.mayAdminister(node[11 .. $],
      page.user.userName);
  }

  /// `mayAdminister`, else answers 403.
  @noRoute bool allowed(HTTPServerResponse res, const PageContext page, string node) {
    if (mayAdminister(page, node))
      return true;
    res.writeBody("Only global account administrators (landscape.manage) and the administrators of this subaccount "
        ~ "may change it", 403, "text/plain; charset=utf-8");
    return false;
  }

  @noRoute bool load(HTTPServerResponse res, PageContext page, string node, out NodeDto n) {
    try {
      n = landscape.node(node);
      return true;
    } catch (PlatformException e) {
      res.writeBody(e.msg, 404, "text/plain; charset=utf-8");
      return false;
    }
  }
}

/// "the global account ACME", "directory shop", "subaccount shop-prod"
string label(const NodeDto n) pure {
  return n.kind == "global" ? "the global account" : n.kind ~ " " ~ n.key;
}

/// Names separated by commas, spaces or lines.
string[] words(string text) pure {
  string[] result;
  foreach (line; text.splitter('\n'))
    foreach (part; line.splitter(','))
      foreach (w; part.splitter(' '))
        if (w.strip.length)
          result ~= w.strip;
  return result;
}

/// "∞" for unlimited quotas.
string quotaText(long quota) pure {
  return quota == unlimited ? "∞" : quota.to!string;
}

/// Money with two decimals ("12.30 EUR").
string money(double amount, string currency) pure {
  import std.format : format;

  return format("%.2f %s", amount, currency);
}

/// Badge classes of a disaster recovery status.
string recoveryBadge(string status) pure nothrow {
  switch (status) {
  case "protected":
    return "bg-green-lt";
  case "failed-over":
    return "bg-orange-lt";
  case "misconfigured":
    return "bg-red-lt";
  default:
    return "bg-secondary-lt";
  }
}

/// "45 min", "4 h", "1 h 30 min"
string minutesText(long minutes) pure {
  if (minutes < 60)
    return minutes.to!string ~ " min";
  auto h = minutes / 60, m = minutes % 60;
  return h.to!string ~ " h" ~ (m ? " " ~ m.to!string ~ " min" : "");
}

///
unittest {
  assert(minutesText(45) == "45 min" && minutesText(240) == "4 h" && minutesText(90) == "1 h 30 min");
  assert(recoveryBadge("protected") == "bg-green-lt" && recoveryBadge("x") == "bg-secondary-lt");
}

/// Colour of a stage badge.
string stageColor(string stage) pure nothrow {
  switch (stage) {
  case "prod":
    return "red";
  case "qa":
    return "orange";
  case "test":
    return "yellow";
  case "dev":
    return "azure";
  default:
    return "secondary";
  }
}

///
unittest {
  assert(words("jane, joe\nann") == ["jane", "joe", "ann"]);
  assert(quotaText(-1) == "∞" && quotaText(3) == "3" && money(12.3, "EUR") == "12.30 EUR");
}
