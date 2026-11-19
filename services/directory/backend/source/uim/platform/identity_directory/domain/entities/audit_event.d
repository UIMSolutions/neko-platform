/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.entities.audit_event;

import neko.directory;

mixin(ShowModule!());

@safe:

/// An immutable entry of the audit log (who did what to which object, and the outcome).
/// The event time is `createdAt`.
struct AuditEvent {
  mixin TenantEntity!AuditEventId;

  AuditEventType eventType = AuditEventType.custom;
  AuditOutcome outcome = AuditOutcome.success;
  string actorId;
  ActorType actorType = ActorType.user;
  string targetId;
  string targetType; /// "User", "Group", "Schema", "PasswordPolicy", "ApiClient"
  string targetName;
  string description;
  string ipAddress;
  string userAgent;
  KeyValue[] details;
}
