/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// IP allow and deny lists, and the network policy that applies them.
///
/// Every request belongs to an area: the public site ("public": /, /media,
/// assets, /health), the management pages ("admin") or the APIs ("api":
/// REST, OData, /api, /metrics). A rule applies to one area or to all.
///
///   1. A deny rule that matches the client blocks it.
///   2. If allow rules apply to the request's area, the client must match one
///      of them (the allow list is a whitelist).
///   3. Otherwise the request passes.
module neko.platform.domain.entities.iprule;

import std.datetime.systime : SysTime;
import std.string : strip;
import neko.platform.domain.exceptions;
import neko.platform.domain.types;

@safe:

enum IpAction {
  allow,
  deny,
}

/// What a rule covers.
enum NetworkScope {
  /// Every request, also the public site.
  all,
  /// Sign-in and the management pages.
  admin,
  /// REST, OData, /api, /metrics.
  api,
}

/// Where a request goes (for the policy).
enum RequestArea {
  public_,
  admin,
  api,
}

alias IpRuleId = Id!"iprule";

struct IpRule {
  IpRuleId id;
  IpNetwork network;
  IpAction action;
  NetworkScope scope_;
  string note;
  string createdBy;
  SysTime createdAt;

  bool appliesTo(RequestArea area) const pure nothrow {
    final switch (scope_) {
    case NetworkScope.all:
      return true;
    case NetworkScope.admin:
      return area == RequestArea.admin;
    case NetworkScope.api:
      return area == RequestArea.api;
    }
  }

  void describe(string note) {
    auto n = note.strip;
    if (n.length > 200)
      throw new ValidationException("Note exceeds 200 characters");
    this.note = n;
  }
}

/// The outcome of the policy for one request.
struct NetworkDecision {
  bool allowed = true;
  /// Why it was blocked ("" if allowed).
  string reason;
  /// The deciding rule, if any.
  string ruleId;
}

NetworkDecision decide(const(IpRule)[] rules, const IpAddress client, RequestArea area) pure {
  foreach (r; rules)
    if (r.action == IpAction.deny && r.appliesTo(area) && r.network.contains(client))
      return NetworkDecision(false, "the address " ~ client.toString ~ " is on the deny list ("
          ~ r.network.toString ~ ")", r.id.value);
  bool listed;
  foreach (r; rules)
    if (r.action == IpAction.allow && r.appliesTo(area)) {
      if (r.network.contains(client))
        return NetworkDecision(true, "", r.id.value);
      listed = true;
    }
  if (listed)
    return NetworkDecision(false, "the address " ~ client.toString ~ " is not on the allow list for this area");
  return NetworkDecision(true);
}

/// True if an allow rule lists the client for every area it uses (exempts
/// it from rate limits and automatic bans).
bool isAllowlisted(const(IpRule)[] rules, const IpAddress client) pure nothrow {
  foreach (r; rules)
    if (r.action == IpAction.allow && r.network.contains(client))
      return true;
  return false;
}

///
unittest {
  IpRule rule(string net, IpAction action, NetworkScope s, string id = "r") {
    IpRule r;
    r.id = IpRuleId(id);
    r.network = IpNetwork(net);
    r.action = action;
    r.scope_ = s;
    return r;
  }

  auto office = parseIpAddress("10.1.2.3"), home = parseIpAddress("203.0.113.9"), bad = parseIpAddress("198.51.100.66");
  IpRule[] rules;
  assert(decide(rules, home, RequestArea.admin).allowed); // no rules: open

  rules ~= rule("10.0.0.0/8", IpAction.allow, NetworkScope.admin, "lan");
  assert(decide(rules, office, RequestArea.admin).allowed);
  assert(!decide(rules, home, RequestArea.admin).allowed);
  assert(decide(rules, home, RequestArea.public_).allowed && decide(rules, home, RequestArea.api).allowed);

  rules ~= rule("198.51.100.0/24", IpAction.deny, NetworkScope.all, "bad");
  auto d = decide(rules, bad, RequestArea.public_);
  assert(!d.allowed && d.ruleId == "bad");
  rules ~= rule("198.51.100.66", IpAction.allow, NetworkScope.admin);
  assert(!decide(rules, bad, RequestArea.admin).allowed); // deny wins

  rules ~= rule("2001:db8::/32", IpAction.allow, NetworkScope.api, "v6");
  assert(!decide(rules, office, RequestArea.api).allowed && decide(rules, parseIpAddress("2001:db8::5"), RequestArea.api).allowed);
  assert(isAllowlisted(rules, office) && !isAllowlisted(rules, home));
}
