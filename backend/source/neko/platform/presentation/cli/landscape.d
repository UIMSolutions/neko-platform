/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `landscape …` commands: the account hierarchy, recommendations, billing.
module neko.platform.presentation.cli.landscape;

import std.array : join, replicate;
import std.conv : to;
import std.format : format;
import vibe.data.json : serializeToJson;
import neko.platform.domain : CallRequest, ValidationException;
import neko.platform.domain.entities.landscape : unlimited;
import neko.platform.presentation.cli.users : list;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;

int landscapeCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "tree");
  switch (sub) {
  case "tree":
    auto view = c.landscape.overview(a.opt("month"));
    if (output.json) {
      output.value(serializeToJson(view));
      return 0;
    }
    string[][] rows;
    foreach (t; view.tree) {
      auto mark = t.kind == "global" ? "◆" : t.kind == "directory" ? "▸" : "•";
      string[] flags;
      if (t.manageEntitlements)
        flags ~= "E";
      if (t.manageAuthorizations)
        flags ~= "A";
      rows ~= ["  ".replicate(t.level) ~ mark ~ " " ~ t.key, t.kind == "subaccount" ? t.stage : flags.join(""),
        t.region, t.subdomain, t.domain, format("%.2f", t.monthCost),
        t.errors ? t.errors.to!string ~ " error(s)" : t.advice ? t.advice.to!string ~ " advice" : ""];
    }
    output.table(["NODE", "STAGE/DIR", "REGION", "SUBDOMAIN", "DOMAIN", "COST " ~ view.month ~ " " ~ view.currency,
      "NOTES"], rows);
    return 0;
  case "show":
    auto n = c.landscape.node(a.word(2, "node (global, directory:<key>, subaccount:<key>)"), a.opt("month"));
    if (output.json) {
      output.value(serializeToJson(n));
      return 0;
    }
    string[][] rows = [["Kind", n.kind], ["Name", n.name]];
    if (n.kind == "subaccount")
      rows ~= [["Region", n.region ~ " (" ~ n.regionLabel ~ ")"], ["Subdomain", n.subdomain],
        ["Purpose / stage", n.purpose ~ " / " ~ n.stage], ["Domain", n.domain], ["Sites", n.sites.join(", ")],
        ["Administrators", n.admins.join(", ")], ["User group", n.members.join(", ")],
        ["Services", n.services.length ? n.services.join(", ") : "all"]];
    if (n.kind == "global")
      rows ~= ["Administrators", n.admins.join(", ")];
    foreach (t; n.tenants)
      foreach (sp; t.spaces)
        rows ~= ["Tenant / space", t.key ~ (t.isDefault ? " (default)" : "") ~ " / " ~ sp.key
            ~ (sp.sites.length ? ": " ~ sp.sites.join(", ") : "")];
    if (n.kind == "directory")
      rows ~= [["Parent", n.parent.length ? n.parent : "global"], ["Entitlements", n.manageEntitlements ? "own" : "inherited"],
        ["Authorizations", n.manageAuthorizations ? "own" : "inherited"], ["Owner", n.owner]];
    rows ~= ["Cost center", n.effectiveCostCenter];
    if (n.entitlementSource.length)
      rows ~= ["Draws from", n.entitlementSource];
    foreach (e; n.entitlements)
      rows ~= ["Entitlement", e.plan ~ ": " ~ (e.quota == unlimited ? "unlimited" : e.quota.to!string)
          ~ (n.kind == "subaccount" ? "" : " (assigned below " ~ e.assignedBelow.to!string ~ ")")];
    foreach (rc; n.roleCollections)
      rows ~= ["Role collection", rc.name ~ ": " ~ rc.rights.join(",") ~ " → " ~ rc.members.join(",")];
    foreach (i; n.inherited)
      rows ~= ["Inherited", i.collection.name ~ " from " ~ i.origin];
    rows ~= ["Costs", format("%.2f", n.monthCost)];
    output.table(["FIELD", "VALUE"], rows);
    return 0;
  case "advise", "check":
    auto view = c.landscape.overview();
    if (output.json) {
      output.value(serializeToJson(["issues": serializeToJson(view.issues), "advice": serializeToJson(view.advice)]));
      return view.issues.length ? 1 : 0;
    }
    string[][] rows;
    foreach (i; view.issues)
      rows ~= [i.severity, i.node, i.message];
    foreach (ad; view.advice)
      rows ~= ["advice", ad.node, ad.recommendation ~ " — " ~ ad.reason];
    if (rows.length)
      output.table(["KIND", "NODE", "MESSAGE"], rows);
    else
      output.message("No problems, no recommendations.");
    // a non-zero exit code on errors makes `landscape check` usable in pipelines
    foreach (i; view.issues)
      if (i.severity == "error")
        return 1;
    return 0;
  case "billing":
    if (a.flag("csv")) {
      output.raw(c.billing.csv(a.opt("month")));
      return 0;
    }
    auto bill = c.billing.bill(a.opt("month"));
    if (output.json) {
      output.value(serializeToJson(bill));
      return 0;
    }
    string[][] rows;
    foreach (r; bill.rows)
      rows ~= ["  ".replicate(r.level) ~ r.key, r.costCenter, r.kind == "subaccount" ? r.requests.to!string : "",
        format("%.2f", r.total)];
    output.table(["NODE", "COST CENTER", "REQUESTS", "TOTAL " ~ bill.currency], rows);
    output.message(format("Total %s: %.2f %s", bill.month, bill.total, bill.currency));
    return 0;
  case "access":
    auto key = a.word(2, "subaccount");
    auto n = c.landscape.node("subaccount:" ~ key);
    auto r = SubaccountAccessRequest(a.has("admins") ? list(a.opt("admins")) : n.admins, a.has("members")
        ? list(a.opt("members")) : n.members, a.has("services") ? list(a.opt("services")) : n.services);
    auto after = c.landscape.setSubaccountAccess(key, r, actor);
    output.message("Administrators: " ~ after.admins.join(", ") ~ "; user group: " ~ after.members.join(", ")
        ~ "; services: " ~ (after.services.length ? after.services.join(", ") : "all"));
    return 0;
  case "tenant":
    auto op = a.word(2, "add|update|remove");
    auto key = a.word(3, "subaccount"), tenant = a.word(4, "tenant");
    if (op == "remove")
      c.landscape.removeTenant(key, tenant, actor);
    else
      c.landscape.saveTenant(key, TenantRequest(tenant, a.opt("name"), a.opt("description"), a.flag("default")),
        op == "add", actor);
    output.message((op == "remove" ? "Removed" : "Saved") ~ " tenant " ~ key ~ "/" ~ tenant);
    return 0;
  case "space":
    auto op = a.word(2, "add|update|remove");
    auto key = a.word(3, "subaccount"), tenant = a.word(4, "tenant"), space = a.word(5, "space");
    if (op == "remove")
      c.landscape.removeSpace(key, tenant, space, actor);
    else
      c.landscape.saveSpace(key, tenant, SpaceRequest(space, a.opt("name"), a.opt("description"),
        list(a.opt("sites"))), op == "add", actor);
    output.message((op == "remove" ? "Removed" : "Saved") ~ " space " ~ key ~ "/" ~ tenant ~ "/" ~ space);
    return 0;
  case "resolve":
    auto call = c.landscape.resolveCall(CallRequest(a.opt("host"), a.opt("subaccount"), a.opt("tenant"),
      a.opt("space"), a.opt("site")));
    call.globalAccount = c.account.key;
    if (output.json) {
      output.value(serializeToJson(call));
      return 0;
    }
    output.table(["GLOBAL ACCOUNT", "SUBACCOUNT", "TENANT", "SPACE", "BY"], [[call.globalAccount, call.subaccount,
      call.tenant, call.space, call.source]]);
    return 0;
  default:
    throw new ValidationException("Unknown landscape command '" ~ sub ~ "'");
  }
}
