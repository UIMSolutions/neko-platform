/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `landscape …` commands: the account hierarchy, recommendations, billing,
/// service assignments and disaster recovery.
module neko.platform.presentation.cli.landscape;

import std.array : join, replicate;
import std.string : toUpper;
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
        ["Purpose / stage", n.purpose ~ " / " ~ n.stage], ["Domain", n.domain],
        ["Disaster recovery", n.recoveryStatus ~ (n.secondaryRegion.length ? " (to " ~ n.secondaryRegion ~ ", running in "
          ~ n.activeRegion ~ ")" : "")], ["Files", n.files.to!string ~ " (" ~ byteSize(n.fileBytes) ~ ")"],
        ["Administrators", n.admins.join(", ")], ["User group", n.members.join(", ")],
        ["Services", n.services.length ? n.services.join(", ") : "all"]];
    if (n.kind == "global")
      rows ~= ["Administrators", n.admins.join(", ")];
    foreach (t; n.tenants)
      foreach (sp; t.spaces)
        rows ~= ["Tenant / space", t.key ~ (t.isDefault ? " (default)" : "") ~ " / " ~ sp.key];
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
      c.landscape.saveSpace(key, tenant, SpaceRequest(space, a.opt("name"), a.opt("description")), op == "add",
        actor);
    output.message((op == "remove" ? "Removed" : "Saved") ~ " space " ~ key ~ "/" ~ tenant ~ "/" ~ space);
    return 0;
  case "resolve":
    auto call = c.landscape.resolveCall(CallRequest(a.opt("host"), a.opt("subaccount"), a.opt("tenant"),
      a.opt("space")));
    call.globalAccount = c.account.key;
    if (output.json) {
      output.value(serializeToJson(call));
      return 0;
    }
    output.table(["GLOBAL ACCOUNT", "SUBACCOUNT", "TENANT", "SPACE", "REGION", "BY"], [[call.globalAccount,
      call.subaccount, call.tenant, call.space, call.region, call.source]]);
    return 0;
  case "assignments":
    auto view = c.landscape.serviceAssignments();
    if (output.json) {
      output.value(serializeToJson(view));
      return 0;
    }
    string[] header = ["SERVICE"];
    foreach (x; view.subaccounts)
      header ~= x.key.toUpper ~ (x.allServices ? " (ALL)" : "");
    string[][] rows;
    foreach (row; view.services) {
      string[] line = [row.service.key];
      foreach (cell; row.cells) {
        string[] quotas;
        foreach (e; cell.entitlements)
          quotas ~= e.plan ~ "=" ~ (e.quota == unlimited ? "∞" : e.quota.to!string);
        line ~= (cell.assigned ? (cell.usedBy.length ? "yes*" : "yes") : "–") ~ (quotas.length ? " "
            ~ quotas.join(" ") : "");
      }
      rows ~= line;
    }
    output.table(header, rows);
    output.message("* used by a role collection of the subaccount (cannot be unassigned)");
    return 0;
  case "assign", "unassign":
    auto service = a.word(2, "service");
    auto target = a.word(3, "subaccount[,…] or all");
    string[] keys;
    if (target == "all")
      foreach (x; c.landscape.serviceAssignments().subaccounts)
        keys ~= x.key;
    else
      keys = list(target);
    c.landscape.assignService(ServiceAssignmentRequest(service, keys, sub == "assign"), actor);
    output.message((sub == "assign" ? "Assigned " ~ service ~ " to " : "Unassigned " ~ service ~ " from ")
        ~ keys.join(", "));
    return 0;
  case "recovery":
    return recoveryCommand(c, a, actor, output);
  default:
    throw new ValidationException("Unknown landscape command '" ~ sub ~ "'");
  }
}

/// `landscape recovery …`
private int recoveryCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto op = a.wordOr(2, "list");
  switch (op) {
  case "list":
    auto view = c.landscape.recoveryOverview();
    if (output.json) {
      output.value(serializeToJson(view));
      return 0;
    }
    string[][] rows;
    foreach (d; view.subaccounts)
      rows ~= [d.subaccount, d.stage, d.status, d.primaryRegion, d.secondaryRegion.length ? d.secondaryRegion : "–",
        d.activeRegion, d.enabled ? d.strategy : "–", d.enabled ? d.rpoMinutes.to!string ~ "/" ~ d.rtoMinutes.to!string
        : "–", d.lastDrillAt.length ? d.lastDrillAt[0 .. 10] : "never"];
    output.table(["SUBACCOUNT", "STAGE", "STATUS", "PRIMARY", "SECONDARY", "ACTIVE", "STRATEGY", "RPO/RTO MIN",
      "LAST DRILL"], rows);
    output.message(format("%s protected, %s failed over, %s misconfigured, %s unprotected (%s in production)",
      view.protectedCount, view.failedOverCount, view.misconfiguredCount, view.unprotectedCount,
      view.unprotectedProduction));
    return 0;
  case "show":
    return showRecovery(output, c.landscape.recovery(a.word(3, "subaccount")));
  case "plan":
    auto key = a.word(3, "subaccount");
    RecoveryPlanRequest r;
    if (a.flag("disable")) {
      auto current = c.landscape.recovery(key);
      r = RecoveryPlanRequest(false, current.secondaryRegion, current.strategy, current.rpoMinutes, current.rtoMinutes);
    } else
      r = RecoveryPlanRequest(true, a.opt("secondary"), a.opt("strategy", "warm-standby"),
        a.opt("rpo", "15").to!long, a.opt("rto", "60").to!long);
    return showRecovery(output, c.landscape.configureRecovery(key, r, actor));
  case "failover", "failback":
    auto key = a.word(3, "subaccount");
    auto r = RecoveryActionRequest(a.opt("reason"), a.opt("minutes", "0").to!long);
    auto d = op == "failover" ? c.landscape.failover(key, r, actor) : c.landscape.failback(key, r, actor);
    output.message(d.subaccount ~ " runs in " ~ d.activeRegion ~ ".");
    return 0;
  case "drill":
    auto key = a.word(3, "subaccount");
    if (!a.has("minutes"))
      throw new ValidationException("Missing option --minutes= (how long the failover took)");
    auto d = c.landscape.recordDrill(key, RecoveryDrillRequest(a.opt("minutes").to!long, !a.flag("failed"),
      a.opt("notes")), actor);
    output.message("Drill of " ~ d.subaccount ~ (d.history[0].success ? " passed" : " failed") ~ ": "
        ~ d.history[0].minutes.to!string ~ " min against an RTO of " ~ d.rtoMinutes.to!string ~ " min"
        ~ (d.history[0].reason.length ? " (" ~ d.history[0].reason ~ ")" : ""));
    return d.history[0].success ? 0 : 1;
  default:
    throw new ValidationException("Unknown recovery command '" ~ op ~ "'");
  }
}

private int showRecovery(CliOutput output, RecoveryDto d) {
  if (output.json) {
    output.value(serializeToJson(d));
    return 0;
  }
  string[][] rows = [["Subaccount", d.subaccount ~ " (" ~ d.stage ~ ", " ~ d.domain ~ ")"], ["Status", d.status],
    ["Primary region", d.primaryRegion ~ " (" ~ d.primaryLabel ~ ")"],
    ["Secondary region", d.secondaryRegion.length ? d.secondaryRegion ~ " (" ~ d.secondaryLabel ~ ")" : "–"],
    ["Active region", d.activeRegion], ["Strategy", d.enabled ? d.strategyLabel : "–"],
    ["RPO / RTO", d.enabled ? d.rpoMinutes.to!string ~ " / " ~ d.rtoMinutes.to!string ~ " min" : "–"],
    ["Last drill", d.lastDrillAt.length ? d.lastDrillAt : "never"],
    ["Last failover", d.lastFailoverAt.length ? d.lastFailoverAt : "never"]];
  foreach (i; d.issues)
    rows ~= [i.error ? "Error" : "Warning", i.message];
  foreach (ad; d.advice)
    rows ~= ["Advice", ad.recommendation ~ " — " ~ ad.reason];
  foreach (e; d.history)
    rows ~= ["History", (e.at.length >= 16 ? e.at[0 .. 16] : e.at) ~ " " ~ e.kind ~ (e.kind == "drill" ? (e.success
        ? " passed" : " failed") : "") ~ " " ~ e.from ~ (e.from != e.to ? " → " ~ e.to : "") ~ " by " ~ e.actor
        ~ (e.reason.length ? ": " ~ e.reason : "")];
  output.table(["FIELD", "VALUE"], rows);
  return 0;
}
