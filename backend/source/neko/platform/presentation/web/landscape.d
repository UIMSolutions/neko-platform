/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The account hierarchy and billing (web interface; htmx fragments).
///
///   GET  /landscape?node=&month=               tree, node details, recommendations   landscape.read
///   GET  /landscape/global/edit, POST /landscape/global                              landscape.manage
///   GET  /landscape/directories/new?parent=, POST /landscape/directories             landscape.manage
///   GET  /landscape/directories/:key/edit, POST /landscape/directories/:key[/delete] landscape.manage
///   GET  /landscape/subaccounts/new?directory=, POST /landscape/subaccounts          landscape.manage
///   GET  /landscape/subaccounts/:key/edit, POST /landscape/subaccounts/:key[/delete] landscape.manage
///   GET  /landscape/entitlement?node=&plan=, POST /landscape/entitlement[/delete]    landscape.manage
///   GET  /landscape/rolecollection?node=&name=, POST /landscape/rolecollection[/delete]  landscape.manage
///   GET  /landscape/billing?month=, GET /landscape/billing.csv?month=                billing.read
///   GET  /landscape/plans/new, /landscape/plans/:key/edit, POST /landscape/plans[/:key/delete]  landscape.manage
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
import neko.platform.ports.usecases : IBillingUseCase, IManageLandscapeUseCase, IManageRolesUseCase,
  IManageSitesUseCase;
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

struct PlanForm {
  bool existing;
  ServicePlanRequest values;
  string error;
}

@requiresAuth
class LandscapeWeb {
  private WebGuard guard;
  private IManageLandscapeUseCase landscape;
  private IBillingUseCase billing;
  private IManageSitesUseCase sites;

  mixin PageAuthentication;

  this(WebGuard guard, IManageLandscapeUseCase landscape, IBillingUseCase billing, IManageSitesUseCase sites) {
    this.guard = guard;
    this.landscape = landscape;
    this.billing = billing;
    this.sites = sites;
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
      s.subdomain, s.purpose, s.stage, s.domain, s.sites, s.costCenter, s.betaFeatures));
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
      req.form.get("domain", ""), req.form.getAll("sites").dup, req.form.get("costCenter", ""),
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
    auto siteList = sites.list("system");
    auto regionList = regions.dup;
    render!("landscape_subaccount_dialog.dt", page, form, view, g, siteList, regionList);
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

  @auth(Role.landscapeManage) @path("/landscape/rolecollection")
  void getRoleCollection(PageContext page, HTTPServerResponse res, string node, string name = "") {
    NodeDto n;
    if (!load(res, page, node, n))
      return;
    auto form = RoleCollectionForm(node, label(n));
    foreach (rc; n.roleCollections)
      if (rc.name == name) {
        form.existing = true;
        form.values = RoleCollectionRequest(rc.name, rc.description, rc.rights.dup, rc.members.dup);
      }
    roleCollectionDialog(page, form);
  }

  @auth(Role.landscapeManage) @path("/landscape/rolecollection")
  void postRoleCollection(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
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

  @auth(Role.landscapeManage) @path("/landscape/rolecollection/delete")
  void postDeleteRoleCollection(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto node = req.form.get("node", ""), name = req.form.get("name", "");
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
    render!("landscape_body.dt", page, view, selected);
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
