/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.services.audit_trail;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Application service: writes audit log entries for every change made by the
/// interactors (and for sign-ins). The audit log itself is append-only.
class AuditTrail {
  protected IAuditRepository repo;
  protected NowFn clock;

  this(IAuditRepository repo, NowFn clock) {
    this.repo = repo;
    this.clock = clock;
  }

  AuditEvent record(TenantId tenantId, AuditEventType type, UserId actor, string targetType, string targetId,
      string targetName, string description, AuditOutcome outcome = AuditOutcome.success,
      KeyValue[] details = null, string ipAddress = "") {
    auto e = AuditEvent(tenantId);
    e.createdAt = clock();
    e.updatedAt = e.createdAt;
    e.createdBy = actor;
    e.updatedBy = actor;
    e.eventType = type;
    e.outcome = outcome;
    e.actorId = actor.value;
    e.actorType = actor.value == "system" || actor.value.length == 0 ? ActorType.system : ActorType.user;
    e.targetType = targetType;
    e.targetId = targetId;
    e.targetName = targetName;
    e.description = description;
    e.details = details;
    e.ipAddress = ipAddress;
    repo.save(e);
    return e;
  }
}
