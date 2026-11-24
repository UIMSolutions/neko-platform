/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Security page (web interface): firewall, network traffic, IP lists, bans.
///
///   GET  /security                   page                            security.read
///   GET  /security/live              traffic, events, bans (10 s)    security.read
///   GET  /security/rules/new         IP rule dialog (?network=&action=)  security.manage
///   POST /security/rules             add an IP rule                  security.manage
///   POST /security/rules/:id/delete  remove an IP rule               security.manage
///   POST /security/ban               ban an address (address, minutes)  security.manage
///   POST /security/unban             lift a ban (address)            security.manage
module neko.platform.presentation.web.security;

import core.time : minutes;
import std.conv : to;
import std.datetime.systime : Clock;
import std.datetime.timezone : UTC;
import std.string : strip;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : AddIpRuleRequest, IpRuleDto;
import neko.platform.domain : PlatformException;
import neko.platform.domain.types.ipnetwork;
import neko.platform.infrastructure.firewall;
import neko.platform.infrastructure.monitoring.traffic : TrafficMonitor, TrafficSnapshot;
import neko.platform.ports.messaging : IEventPublisher, PlatformEvent;
import neko.platform.ports.usecases : IManageNetworkUseCase;
import neko.platform.presentation.http.firewall : clientAddressOf;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.support;

@safe:

/// The firewall settings shown on the page.
struct FirewallInfo {
  string mode;
  long rateLimit;
  long banAfter;
  long banMinutes;
  string trustedProxies;
}

/// Values of the IP rule dialog.
struct IpRuleForm {
  string network;
  string action = "allow";
  string scope_ = "admin";
  string note;
  string error;
}

@requiresAuth
class SecurityWeb {
  private WebGuard guard;
  private IManageNetworkUseCase network;
  private TrafficMonitor traffic;
  private BanList bans;
  private FirewallInfo info;
  private IEventPublisher events;

  mixin PageAuthentication;

  this(WebGuard guard, IManageNetworkUseCase network, TrafficMonitor traffic, BanList bans, FirewallInfo info,
      IEventPublisher events) {
    this.events = events;
    this.guard = guard;
    this.network = network;
    this.traffic = traffic;
    this.bans = bans;
    this.info = info;
  }

  @auth(Role.securityRead) @path("/security")
  void getSecurity(PageContext page, HTTPServerRequest req) {
    page = page.at("Security", "security");
    auto stats = traffic.snapshot;
    auto active = bans.active(Clock.currTime(UTC()));
    auto rules = network.list();
    auto me = clientAddressOf(req);
    auto settings = info;
    render!("security.dt", page, stats, active, rules, me, settings);
  }

  @auth(Role.securityRead) @path("/security/live")
  void getSecurityLive(PageContext page, HTTPServerRequest req) {
    live(page, req);
  }

  @auth(Role.securityManage) @path("/security/rules/new")
  void getNewRule(PageContext page, HTTPServerRequest req, string network = "", string action = "allow") {
    auto form = IpRuleForm(network, action == "deny" ? "deny" : "allow", action == "deny" ? "all" : "admin");
    auto me = clientAddressOf(req);
    render!("ip_rule_dialog.dt", page, form, me);
  }

  @auth(Role.securityManage) @path("/security/rules")
  void postRules(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = IpRuleForm(req.form.get("network", ""), req.form.get("action", ""), req.form.get("scope", ""),
      req.form.get("note", ""));
    auto me = clientAddressOf(req);
    try {
      auto added = network.add(AddIpRuleRequest(form.network, form.action, form.scope_, form.note),
        page.user.userName, me);
      rulesTable(res, page, me, added.network ~ " added to the " ~ added.action ~ " list", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("ip_rule_dialog.dt", page, form, me);
    }
  }

  @auth(Role.securityManage) @path("/security/rules/:id/delete")
  void postDeleteRule(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    auto me = clientAddressOf(req);
    try {
      network.remove(_id, page.user.userName, me);
      rulesTable(res, page, me, "IP rule removed", false);
    } catch (PlatformException e)
      rulesTable(res, page, me, e.msg, true);
  }

  @auth(Role.securityManage) @path("/security/ban")
  void postBan(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto address = req.form.get("address", "").strip;
    long length = 60;
    try
      length = req.form.get("minutes", "60").to!long;
    catch (Exception) {
    }
    IpAddress a;
    string message;
    bool error = true;
    if (!tryParseIpAddress(address, a))
      message = "'" ~ address ~ "' is not an IP address";
    else if (a.toString == clientAddressOf(req))
      message = "You cannot ban your own address";
    else if (length < 1 || length > 60 * 24 * 30)
      message = "A ban lasts 1 minute to 30 days";
    else {
      bans.ban(a.toString, Clock.currTime(UTC()), length.minutes, "banned by " ~ page.user.userName);
      audit("security.ban", a.toString, page.user.userName, "Banned " ~ a.toString ~ " for " ~ length.to!string
          ~ " minutes");
      message = a.toString ~ " banned for " ~ length.to!string ~ " minutes";
      error = false;
    }
    swapTable(res, "security-live", message, error);
    live(page, req);
  }

  @auth(Role.securityManage) @path("/security/unban")
  void postUnban(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto address = req.form.get("address", "").strip;
    auto lifted = bans.unban(address);
    if (lifted)
      audit("security.unban", address, page.user.userName, "Lifted the ban of " ~ address);
    swapTable(res, "security-live", lifted ? "Ban of " ~ address ~ " lifted" : address ~ " is not banned", !lifted);
    live(page, req);
  }

  @noRoute void audit(string type, string subject, string actor, string message) {
    events.publish(PlatformEvent(type, subject, actor, message, Clock.currTime(UTC())));
  }

  @noRoute void live(PageContext page, HTTPServerRequest req) {
    auto stats = traffic.snapshot;
    auto active = bans.active(Clock.currTime(UTC()));
    auto rules = network.list();
    auto me = clientAddressOf(req);
    auto settings = info;
    render!("security_live.dt", page, stats, active, rules, me, settings);
  }

  @noRoute void rulesTable(HTTPServerResponse res, PageContext page, string me, string message, bool error) {
    swapTable(res, "ip-rules", message, error);
    auto rules = network.list();
    render!("ip_rules_table.dt", page, rules, me);
  }
}
