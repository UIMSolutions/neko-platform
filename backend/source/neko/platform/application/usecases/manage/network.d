/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// IP allow and deny lists (see domain.entities.iprule for the policy).
module neko.platform.application.usecases.manage.network;

import core.time : Duration, seconds;
import std.algorithm : map, sort;
import std.array : array;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.string : strip, toLower;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.ports;

@safe:

class ManageNetworkUseCase : IManageNetworkUseCase {
  private IIpRuleRepository rules;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  /// Rules are read on every request: cache them, and re-read now and then
  /// so changes made with the CLI reach a running server.
  private IpRule[] cache;
  private SysTime loadedAt;
  private Duration maxAge;

  this(IIpRuleRepository rules, IEventPublisher events, IClock clock, IIdGenerator ids,
      Duration maxAge = 5.seconds) {
    this.rules = rules;
    this.events = events;
    this.clock = clock;
    this.ids = ids;
    this.maxAge = maxAge;
  }

  IpRuleDto[] list() {
    auto all = rules.all;
    all.sort!((a, b) => a.action > b.action || (a.action == b.action && (a.scope_ < b.scope_
        || (a.scope_ == b.scope_ && a.network.toString < b.network.toString))));
    return all.map!(r => r.toDto).array;
  }

  IpRuleDto add(AddIpRuleRequest request, string actor, string actorAddress) {
    IpRule rule;
    rule.id = IpRuleId(ids.newId);
    rule.network = IpNetwork(request.network);
    rule.action = parseAction(request.action);
    rule.scope_ = parseScope(request.scope_);
    rule.describe(request.note);
    rule.createdBy = actor;
    rule.createdAt = clock.now;
    auto all = rules.all;
    foreach (r; all)
      if (r.network == rule.network && r.action == rule.action && r.scope_ == rule.scope_)
        throw new ConflictException("The " ~ rule.action.to!string ~ " list already has " ~ rule.network.toString
            ~ " for " ~ rule.scope_.to!string);
    requireNoLockout(all ~ rule, actorAddress);
    rules.save(rule);
    invalidate();
    events.publish(PlatformEvent("network.rule.added", rule.id.value, actor, "Added " ~ rule.network.toString ~ " to the "
        ~ rule.action.to!string ~ " list (" ~ rule.scope_.to!string ~ ")", clock.now));
    return rule.toDto;
  }

  void remove(string id, string actor, string actorAddress) {
    IpRule rule;
    if (!rules.tryGet(IpRuleId(id.strip), rule))
      throw new NotFoundException("IP rule", id);
    IpRule[] rest;
    foreach (r; rules.all)
      if (r.id != rule.id)
        rest ~= r;
    requireNoLockout(rest, actorAddress);
    rules.remove(rule.id);
    invalidate();
    events.publish(PlatformEvent("network.rule.removed", rule.id.value, actor, "Removed " ~ rule.network.toString
        ~ " from the " ~ rule.action.to!string ~ " list (" ~ rule.scope_.to!string ~ ")", clock.now));
  }

  NetworkDecision check(string address, RequestArea area) {
    IpAddress client;
    if (!tryParseIpAddress(address, client))
      return NetworkDecision(true); // unix socket: no address, local by definition
    return decide(current(), client, area);
  }

  bool isAllowlisted(string address) {
    IpAddress client;
    return tryParseIpAddress(address, client) && .isAllowlisted(current(), client);
  }

  private const(IpRule)[] current() {
    auto now = clock.now;
    if (loadedAt == SysTime.init || now - loadedAt > maxAge) {
      cache = rules.all;
      loadedAt = now;
    }
    return cache;
  }

  private void invalidate() {
    loadedAt = SysTime.init;
  }

  /// The caller must still reach the management pages afterwards.
  private static void requireNoLockout(const(IpRule)[] after, string actorAddress) {
    IpAddress client;
    if (!tryParseIpAddress(actorAddress, client))
      return; // CLI or unix socket
    auto d = decide(after, client, RequestArea.admin);
    if (!d.allowed)
      throw new PolicyViolationException("This change would lock you out: " ~ d.reason
          ~ ". Allow your own address first (or use the CLI on the server).");
  }
}

IpAction parseAction(string text) {
  switch (text.strip.toLower) {
  case "allow", "whitelist", "allowlist":
    return IpAction.allow;
  case "deny", "block", "blacklist", "denylist":
    return IpAction.deny;
  default:
    throw new ValidationException("Action must be 'allow' or 'deny', not '" ~ text ~ "'");
  }
}

NetworkScope parseScope(string text) {
  switch (text.strip.toLower) {
  case "all", "":
    return NetworkScope.all;
  case "admin":
    return NetworkScope.admin;
  case "api":
    return NetworkScope.api;
  default:
    throw new ValidationException("Scope must be 'all', 'admin' or 'api', not '" ~ text ~ "'");
  }
}

///
unittest {
  import neko.platform.application.services : FixedClock, SequentialIds;
  import neko.platform.application.usecases.manage_users : fails, NoEvents;
  import std.datetime.date : DateTime;
  import std.datetime.timezone : UTC;

  class FakeRules : IIpRuleRepository {
    IpRule[string] items;

    IpRule[] all() {
      return items.values;
    }

    bool tryGet(IpRuleId id, out IpRule r) {
      if (auto p = id.value in items) {
        r = *p;
        return true;
      }
      return false;
    }

    void save(IpRule r) {
      items[r.id.value] = r;
    }

    bool remove(IpRuleId id) {
      return items.remove(id.value);
    }
  }

  auto repo = new FakeRules;
  auto uc = new ManageNetworkUseCase(repo, new NoEvents, new FixedClock(SysTime(DateTime(2026, 11, 20), UTC())),
    new SequentialIds("ip"));
  auto me = "10.1.2.3";

  // whitelisting a network that does not contain me: refused
  assert(fails!PolicyViolationException(() { uc.add(AddIpRuleRequest("192.168.0.0/16", "allow", "admin"), "admin", me); }));
  auto lan = uc.add(AddIpRuleRequest("10.0.0.0/8", "allow", "admin", "office"), "admin", me);
  assert(lan.network == "10.0.0.0/8" && lan.scope_ == "admin");
  uc.add(AddIpRuleRequest("192.168.0.0/16", "allow", "admin"), "admin", me);
  assert(fails!ConflictException(() { uc.add(AddIpRuleRequest("10.9.9.9/8", "allow", "admin"), "admin", me); }));
  assert(fails!ValidationException(() { uc.add(AddIpRuleRequest("10.0.0.0/40", "allow", "admin"), "admin", me); }));
  assert(fails!ValidationException(() { uc.add(AddIpRuleRequest("10.0.0.0/8", "maybe", "admin"), "admin", me); }));
  // denying myself, or removing the rule that lets me in: refused
  assert(fails!PolicyViolationException(() { uc.add(AddIpRuleRequest(me, "deny", "all"), "admin", me); }));
  assert(fails!PolicyViolationException(() { uc.remove(lan.id, "admin", me); }));
  uc.remove(lan.id, "cli:root", ""); // the CLI may

  assert(!uc.check("10.1.2.3", RequestArea.admin).allowed && uc.check("192.168.1.1", RequestArea.admin).allowed);
  assert(uc.check("8.8.8.8", RequestArea.public_).allowed && uc.check("", RequestArea.admin).allowed);
  uc.add(AddIpRuleRequest("8.8.8.0/24", "deny", "all", "abuse"), "admin", "192.168.1.1");
  assert(!uc.check("8.8.8.8", RequestArea.public_).allowed);
  assert(uc.isAllowlisted("192.168.4.4") && !uc.isAllowlisted("8.8.8.8"));
  assert(uc.list[0].action == "deny");
}
