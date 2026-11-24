/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Multi-region disaster recovery of subaccounts.
///
/// A subaccount lives in its primary region (`Subaccount.region`, fixed at
/// creation). Its recovery plan names a secondary region, a strategy and the
/// objectives it has to meet:
///
///   RPO  recovery point objective: how much data (minutes) may be lost
///   RTO  recovery time objective: how long (minutes) restoring may take
///
/// Operations: a failover moves the subaccount to its secondary region (the
/// active region; service calls report it in their call context), a failback
/// returns it to the primary region, a drill rehearses a failover and records
/// how long it took against the RTO. Every operation is kept in the plan's
/// history (newest first, `maxRecoveryHistory` entries).
///
/// Rules (`recoveryIssues`): the secondary region exists and differs from the
/// primary one; confidential and secret subaccounts in an EU Access region
/// fail over only to another EU Access (or self-hosted) region; a failed-over
/// subaccount keeps an enabled plan. Warnings: objectives the strategy cannot
/// reach, a secondary region in the same location (no protection from a site
/// failure), and data leaving its geography.
module neko.platform.domain.entities.recovery;

import std.algorithm : canFind, startsWith;
import std.conv : to;
import std.datetime.systime : SysTime;
import std.string : strip, toLower;
import neko.platform.domain.entities.landscape : RegionInfo, Stage, Subaccount, isProduction, tryRegion;
import neko.platform.domain.enumerations.security : SecurityDomain;
import neko.platform.domain.exceptions;

@safe:

/// History entries kept per subaccount.
enum maxRecoveryHistory = 50;

/// How the secondary region is prepared, from cheapest (slowest) to most
/// expensive (fastest).
enum RecoveryStrategy {
  /// Backups are copied to the secondary region and restored on demand.
  backupRestore,
  /// Data is replicated; compute is started on failover.
  pilotLight,
  /// A scaled-down copy runs in the secondary region and is scaled up.
  warmStandby,
  /// Both regions serve; a failover only shifts traffic.
  activeActive,
}

/// Objectives a strategy can reach at best, in minutes.
struct StrategyLimits {
  long minRpoMinutes;
  long minRtoMinutes;
  string label;
}

StrategyLimits limitsOf(RecoveryStrategy s) pure nothrow {
  final switch (s) {
  case RecoveryStrategy.backupRestore:
    return StrategyLimits(60, 240, "Backup & restore");
  case RecoveryStrategy.pilotLight:
    return StrategyLimits(5, 30, "Pilot light");
  case RecoveryStrategy.warmStandby:
    return StrategyLimits(1, 10, "Warm standby");
  case RecoveryStrategy.activeActive:
    return StrategyLimits(0, 0, "Active-active");
  }
}

/// "warm-standby", "warmStandby" or "warm standby" → RecoveryStrategy.warmStandby
RecoveryStrategy parseStrategy(string text) pure {
  string k;
  foreach (c; text.strip.toLower)
    if (c != '-' && c != '_' && c != ' ' && c != '&')
      k ~= c;
  switch (k) {
  case "backuprestore", "backup":
    return RecoveryStrategy.backupRestore;
  case "pilotlight", "pilot":
    return RecoveryStrategy.pilotLight;
  case "warmstandby", "warm", "standby":
    return RecoveryStrategy.warmStandby;
  case "activeactive", "active":
    return RecoveryStrategy.activeActive;
  default:
    throw new ValidationException("Strategy must be backup-restore, pilot-light, warm-standby or active-active, not '"
        ~ text.strip ~ "'");
  }
}

/// "warmStandby" → "warm-standby"
string strategyKey(RecoveryStrategy s) pure nothrow {
  final switch (s) {
  case RecoveryStrategy.backupRestore:
    return "backup-restore";
  case RecoveryStrategy.pilotLight:
    return "pilot-light";
  case RecoveryStrategy.warmStandby:
    return "warm-standby";
  case RecoveryStrategy.activeActive:
    return "active-active";
  }
}

/// Where a region is: "Europe", "Americas", "Asia Pacific"; "" for self-hosted.
string regionArea(string id) pure nothrow {
  if (id.startsWith("eu") || id.startsWith("ch"))
    return "Europe";
  if (id.startsWith("us") || id.startsWith("ca") || id.startsWith("br"))
    return "Americas";
  if (id.startsWith("jp") || id.startsWith("ap") || id.startsWith("in"))
    return "Asia Pacific";
  return "";
}

/// Something that happened to a recovery plan.
struct RecoveryEvent {
  SysTime at;
  /// "plan" | "failover" | "failback" | "drill"
  string kind;
  /// Regions: active before and after (the same for drills and plan changes).
  string from;
  string to;
  string actor;
  string reason;
  /// Measured (drills) or reported (failovers) duration; 0 = not given.
  long minutes;
  /// Drills: whether the rehearsal worked and met the RTO.
  bool success = true;
}

/// The disaster recovery set-up of a subaccount. Disabled = unprotected.
struct RecoveryPlan {
  bool enabled;
  string secondaryRegion;
  RecoveryStrategy strategy = RecoveryStrategy.warmStandby;
  long rpoMinutes = 15;
  long rtoMinutes = 60;
  /// Running in the secondary region.
  bool failedOver;
  SysTime lastFailoverAt;
  SysTime lastDrillAt;
  /// Newest first.
  RecoveryEvent[] history;

  RecoveryPlan copy() const pure nothrow {
    return RecoveryPlan(enabled, secondaryRegion, strategy, rpoMinutes, rtoMinutes, failedOver, lastFailoverAt,
      lastDrillAt, history.dup);
  }

  /// Adds to the history (newest first), forgetting the oldest entries.
  void record(RecoveryEvent e) pure nothrow {
    history = e ~ history;
    if (history.length > maxRecoveryHistory)
      history = history[0 .. maxRecoveryHistory];
  }
}

/// The region serving the subaccount now.
string activeRegion(const Subaccount s) pure nothrow {
  return s.recovery.failedOver && s.recovery.secondaryRegion.length ? s.recovery.secondaryRegion : s.region;
}

/// "protected", "failed-over", "unprotected" or "misconfigured" (has errors).
string recoveryStatus(const Subaccount s) pure {
  foreach (i; recoveryIssues(s))
    if (i.error)
      return "misconfigured";
  if (s.recovery.failedOver)
    return "failed-over";
  return s.recovery.enabled ? "protected" : "unprotected";
}

/// Sets up (or changes) the plan. The subaccount must not be failed over
/// when the secondary region changes.
void configureRecovery(ref Subaccount s, bool enabled, string secondaryRegion, RecoveryStrategy strategy,
    long rpoMinutes, long rtoMinutes, string actor, SysTime now) {
  auto secondary = secondaryRegion.strip.toLower;
  if (rpoMinutes < 0 || rtoMinutes < 0)
    throw new ValidationException("RPO and RTO must be 0 minutes or more");
  if (rpoMinutes > 7 * 24 * 60 || rtoMinutes > 7 * 24 * 60)
    throw new ValidationException("RPO and RTO must be at most one week (10080 minutes)");
  if (enabled) {
    RegionInfo info;
    if (secondary.length == 0)
      throw new ValidationException("Choose a secondary region");
    if (!tryRegion(secondary, info))
      throw new ValidationException("Unknown region '" ~ secondary ~ "'");
    if (secondary == s.region)
      throw new ValidationException("The secondary region must differ from the primary region " ~ s.region);
  }
  if (s.recovery.failedOver && (!enabled || secondary != s.recovery.secondaryRegion))
    throw new InvalidStateTransitionException("The subaccount " ~ s.key ~ " runs in its secondary region "
        ~ s.recovery.secondaryRegion ~ "; fail back first");
  s.recovery.enabled = enabled;
  s.recovery.secondaryRegion = secondary;
  s.recovery.strategy = strategy;
  s.recovery.rpoMinutes = rpoMinutes;
  s.recovery.rtoMinutes = rtoMinutes;
  auto active = activeRegion(s);
  s.recovery.record(RecoveryEvent(now, "plan", active, active, actor, enabled ? limitsOf(strategy).label ~ " to "
      ~ secondary ~ ", RPO " ~ rpoMinutes.to!string ~ " min, RTO " ~ rtoMinutes.to!string ~ " min" : "Disabled"));
}

/// Moves the subaccount to its secondary region.
void failover(ref Subaccount s, string reason, long minutes, string actor, SysTime now) {
  if (!s.recovery.enabled)
    throw new InvalidStateTransitionException("The subaccount " ~ s.key ~ " has no disaster recovery plan");
  if (s.recovery.failedOver)
    throw new InvalidStateTransitionException("The subaccount " ~ s.key ~ " already runs in its secondary region "
        ~ s.recovery.secondaryRegion);
  requireReason(reason);
  s.recovery.failedOver = true;
  s.recovery.lastFailoverAt = now;
  s.recovery.record(RecoveryEvent(now, "failover", s.region, s.recovery.secondaryRegion, actor, reason.strip,
      minutes < 0 ? 0 : minutes));
}

/// Returns the subaccount to its primary region.
void failback(ref Subaccount s, string reason, long minutes, string actor, SysTime now) {
  if (!s.recovery.failedOver)
    throw new InvalidStateTransitionException("The subaccount " ~ s.key ~ " already runs in its primary region "
        ~ s.region);
  requireReason(reason);
  s.recovery.failedOver = false;
  s.recovery.record(RecoveryEvent(now, "failback", s.recovery.secondaryRegion, s.region, actor, reason.strip,
      minutes < 0 ? 0 : minutes));
}

/// Records a failover rehearsal; it succeeded if it worked within the RTO.
/// Returns whether it did.
bool recordDrill(ref Subaccount s, long minutes, bool worked, string notes, string actor, SysTime now) {
  if (!s.recovery.enabled)
    throw new InvalidStateTransitionException("The subaccount " ~ s.key ~ " has no disaster recovery plan");
  if (s.recovery.failedOver)
    throw new InvalidStateTransitionException("The subaccount " ~ s.key ~ " is failed over; drill after the failback");
  if (minutes < 0)
    throw new ValidationException("The duration of a drill must be 0 minutes or more");
  auto success = worked && minutes <= s.recovery.rtoMinutes;
  s.recovery.lastDrillAt = now;
  auto text = notes.strip;
  if (worked && !success)
    text = "RTO missed (" ~ minutes.to!string ~ " > " ~ s.recovery.rtoMinutes.to!string ~ " min)"
      ~ (text.length ? "; " ~ text : "");
  s.recovery.record(RecoveryEvent(now, "drill", s.region, s.recovery.secondaryRegion, actor, text, minutes, success));
  return success;
}

private void requireReason(string reason) {
  auto r = reason.strip;
  if (r.length == 0)
    throw new ValidationException("Give a reason (incident, maintenance, …); it goes into the history");
  if (r.length > 500)
    throw new ValidationException("The reason exceeds 500 characters");
}

/// A rule violation of a recovery plan.
struct RecoveryIssue {
  bool error;
  string message;
}

/// Errors and warnings of the plan of `s` (none for a disabled plan that is
/// not failed over).
RecoveryIssue[] recoveryIssues(const Subaccount s) pure {
  RecoveryIssue[] issues;
  void error(string m) {
    issues ~= RecoveryIssue(true, m);
  }

  void warning(string m) {
    issues ~= RecoveryIssue(false, m);
  }

  auto p = s.recovery;
  if (p.failedOver && !p.enabled)
    error("Runs in its secondary region, but disaster recovery is disabled");
  if (!p.enabled)
    return issues;
  RegionInfo primary, secondary;
  auto knownPrimary = tryRegion(s.region, primary);
  if (p.secondaryRegion.length == 0)
    return [RecoveryIssue(true, "Disaster recovery is enabled without a secondary region")];
  if (!tryRegion(p.secondaryRegion, secondary))
    return [RecoveryIssue(true, "Unknown secondary region '" ~ p.secondaryRegion ~ "'")];
  if (p.secondaryRegion == s.region)
    error("The secondary region is the primary region " ~ s.region);
  auto sensitive = s.domain == SecurityDomain.confidential || s.domain == SecurityDomain.secret;
  if (knownPrimary && sensitive && primary.euAccess && !secondary.euAccess && secondary.provider != "Self-hosted")
    error("Fails over from the EU Access region " ~ s.region ~ " to " ~ p.secondaryRegion ~ ", which is not EU "
        ~ "Access; " ~ s.domain.to!string ~ " data must stay under EU Access");
  auto limits = limitsOf(p.strategy);
  if (p.rpoMinutes < limits.minRpoMinutes)
    warning(limits.label ~ " reaches an RPO of " ~ limits.minRpoMinutes.to!string ~ " minutes at best, the target is "
        ~ p.rpoMinutes.to!string);
  if (p.rtoMinutes < limits.minRtoMinutes)
    warning(limits.label ~ " reaches an RTO of " ~ limits.minRtoMinutes.to!string ~ " minutes at best, the target is "
        ~ p.rtoMinutes.to!string);
  if (knownPrimary && primary.provider == secondary.provider && sameLocation(primary.location, secondary.location))
    warning("The secondary region " ~ p.secondaryRegion ~ " is in the same location as " ~ s.region ~ " ("
        ~ secondary.location ~ "); it does not protect from the loss of that location");
  auto from = regionArea(s.region), to = regionArea(p.secondaryRegion);
  if (from.length && to.length && from != to)
    warning("A failover moves the data from " ~ from ~ " to " ~ to ~ "; check data residency");
  return issues;
}

/// "Europe (Frankfurt) – EU Access" and "Europe (Frankfurt)" are one location.
private bool sameLocation(string a, string b) pure nothrow {
  string base(string s) {
    foreach (i, c; s)
      if (c == ')')
        return s[0 .. i + 1];
    return s;
  }

  return base(a) == base(b);
}

/// A recommendation for the recovery of `s`.
struct RecoveryAdvice {
  string recommendation;
  string reason;
}

RecoveryAdvice[] recoveryAdvice(const Subaccount s) pure {
  RecoveryAdvice[] list;
  auto p = s.recovery;
  if (!p.enabled && s.stage.isProduction)
    list ~= RecoveryAdvice("Set up disaster recovery",
      "It is a production subaccount without a secondary region; the loss of " ~ s.region ~ " takes it down.");
  if (p.enabled && p.lastDrillAt == SysTime.init && !p.failedOver)
    list ~= RecoveryAdvice("Run a disaster recovery drill",
      "The failover to " ~ p.secondaryRegion ~ " was never rehearsed; a plan nobody tried is a hope, not a plan.");
  if (p.enabled && p.history.length && p.history[0].kind == "drill" && !p.history[0].success)
    list ~= RecoveryAdvice("Fix the last drill",
      "The last drill failed or missed the RTO of " ~ p.rtoMinutes.to!string ~ " minutes.");
  if (p.failedOver)
    list ~= RecoveryAdvice("Fail back when " ~ s.region ~ " is healthy",
      "It runs in its secondary region " ~ p.secondaryRegion ~ " without a standby of its own.");
  return list;
}

///
unittest {
  import std.algorithm : any;

  Subaccount s;
  s.key = "shop-prod";
  s.region = "eu11";
  s.stage = Stage.prod;
  s.domain = SecurityDomain.confidential;
  auto t0 = SysTime.fromISOExtString("2026-11-24T10:00:00Z");
  assert(recoveryStatus(s) == "unprotected" && recoveryAdvice(s).any!(a => a.recommendation.canFind("Set up")));

  bool fails(E)(void delegate() @safe f) {
    try
      f();
    catch (E)
      return true;
    return false;
  }

  assert(fails!ValidationException(() {
      configureRecovery(s, true, "eu11", RecoveryStrategy.warmStandby, 15, 60, "ann", t0);
    }));
  assert(fails!ValidationException(() {
      configureRecovery(s, true, "mars1", RecoveryStrategy.warmStandby, 15, 60, "ann", t0);
    }));
  // confidential data in EU Access: not to a plain region
  configureRecovery(s, true, "eu20", RecoveryStrategy.warmStandby, 15, 60, "ann", t0);
  assert(recoveryStatus(s) == "misconfigured" && recoveryIssues(s)[0].message.canFind("EU Access"));
  configureRecovery(s, true, "onprem", RecoveryStrategy.backupRestore, 5, 30, "ann", t0);
  auto issues = recoveryIssues(s);
  assert(recoveryStatus(s) == "protected" && issues.length == 2); // RPO and RTO out of reach
  configureRecovery(s, true, "onprem", RecoveryStrategy.pilotLight, 15, 60, "ann", t0);
  assert(recoveryIssues(s).length == 0 && s.recovery.history.length == 3);
  assert(recoveryAdvice(s).any!(a => a.recommendation.canFind("drill")));

  // drills against the RTO
  assert(recordDrill(s, 45, true, "", "ann", t0));
  assert(!recordDrill(s, 90, true, "slow DNS", "ann", t0) && s.recovery.history[0].reason.canFind("RTO missed"));
  assert(recoveryAdvice(s).any!(a => a.recommendation == "Fix the last drill"));

  // failover and failback
  assert(fails!ValidationException(() { failover(s, " ", 0, "ann", t0); }));
  failover(s, "eu11 outage", 25, "ann", t0);
  assert(activeRegion(s) == "onprem" && recoveryStatus(s) == "failed-over" && s.recovery.lastFailoverAt == t0);
  assert(fails!InvalidStateTransitionException(() { failover(s, "again", 0, "ann", t0); }));
  assert(fails!InvalidStateTransitionException(() { recordDrill(s, 1, true, "", "ann", t0); }));
  assert(fails!InvalidStateTransitionException(() {
      configureRecovery(s, true, "eu10", RecoveryStrategy.pilotLight, 15, 60, "ann", t0);
    }));
  failback(s, "eu11 healthy", 0, "ann", t0);
  assert(activeRegion(s) == "eu11" && s.recovery.history[0].kind == "failback");
  assert(fails!InvalidStateTransitionException(() { failback(s, "x", 0, "ann", t0); }));

  // same location, history limit
  Subaccount d;
  d.region = "eu10";
  configureRecovery(d, true, "eu11", RecoveryStrategy.activeActive, 0, 0, "ann", t0);
  assert(recoveryIssues(d).length == 1 && recoveryIssues(d)[0].message.canFind("same location"));
  foreach (i; 0 .. maxRecoveryHistory + 5)
    recordDrill(d, 0, true, "", "ann", t0);
  assert(d.recovery.history.length == maxRecoveryHistory);
  assert(parseStrategy("Warm Standby") == RecoveryStrategy.warmStandby && strategyKey(RecoveryStrategy.pilotLight)
      == "pilot-light");
  assert(regionArea("ch20") == "Europe" && regionArea("onprem") == "");
}
