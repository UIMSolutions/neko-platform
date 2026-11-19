/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.manage.audit_log;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Interactor: the audit log. External components may append entries;
/// entries are never changed and only removed by retention (purge).
class AuditLogUseCase : IAuditLogUseCase {
  protected IAuditRepository repo;
  protected AuditTrail audit;

  this(DirectoryRepositories repos, AuditTrail audit) {
    this.repo = repos.auditEvents;
    this.audit = audit;
  }

  UsecaseResult create(CreateAuditEventRequest r) {
    return guarded(() {
      validate(!r.tenantId.isEmpty, "Tenant ID is required");
      validate(r.spec.description.strip.length > 0 || r.spec.eventType != AuditEventType.custom,
        "An audit event needs an event type or a description");
      auto e = AuditEvent(r.tenantId);
      assignMatching(e, r.spec);
      e.actorId = e.actorId.length ? e.actorId : r.actor.value;
      e.createdBy = r.actor;
      e.updatedBy = r.actor;
      repo.save(e);
      return succeeded(e.id.value, "Audit event " ~ enumText(e.eventType) ~ " recorded");
    });
  }

  UsecaseResult update(UpdateAuditEventRequest r) {
    return UsecaseResult(false, "", "Audit events are immutable", 409);
  }

  UsecaseResult remove(TenantId tenantId, AuditEventId id, UserId actor) {
    if (repo.findById(tenantId, id).isNull)
      return UsecaseResult(false, "", "Audit event '" ~ id.value ~ "' not found", 404);
    return UsecaseResult(false, "", "Audit events are immutable — they are removed by the retention period only", 409);
  }

  AuditEvent get(TenantId tenantId, AuditEventId id) {
    return repo.findById(tenantId, id);
  }

  /// Newest first.
  AuditEvent[] list(TenantId tenantId) {
    auto items = repo.findByTenant(tenantId);
    items.sort!((a, b) => a.createdAt > b.createdAt);
    return items;
  }

  UsecaseResult purge(TenantId tenantId, long before, UserId actor) {
    auto old = repo.findMatching(tenantId, (const AuditEvent e) => e.createdAt < before);
    foreach (e; old)
      repo.remove(e);
    if (old.length > 0)
      audit.record(tenantId, AuditEventType.auditPurged, actor, "AuditLog", "", "",
        old.length.to!string ~ " audit event(s) older than " ~ isoText(before) ~ " purged");
    return succeeded(old.length.to!string, old.length.to!string ~ " audit event(s) purged");
  }
}
