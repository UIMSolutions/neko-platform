/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Business enumerations of credentials, API clients and the audit log.
module neko.directory.domain.enumerations.security;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Strength class of a password policy (derived from its rules).
enum PasswordStrength {
  basic,
  standard,
  strong,
  enterprise,
}

/// Lifecycle of an API client (technical user).
enum ApiClientStatus {
  active,
  revoked,
  expired,
}

/// Who performed an audited action.
enum ActorType {
  user,
  apiClient,
  system,
}

/// Outcome of an audited action.
enum AuditOutcome {
  success,
  failure,
}

/// Audited event types (SAP Audit Log style names).
enum AuditEventType : string {
  userCreated = "USER_CREATED",
  userUpdated = "USER_UPDATED",
  userDeleted = "USER_DELETED",
  userActivated = "USER_ACTIVATED",
  userDeactivated = "USER_DEACTIVATED",
  userLocked = "USER_LOCKED",
  userUnlocked = "USER_UNLOCKED",
  passwordChanged = "PASSWORD_CHANGED",
  passwordReset = "PASSWORD_RESET",
  passwordExpired = "PASSWORD_EXPIRED",
  loginSuccess = "LOGIN_SUCCESS",
  loginFailure = "LOGIN_FAILURE",
  groupCreated = "GROUP_CREATED",
  groupUpdated = "GROUP_UPDATED",
  groupDeleted = "GROUP_DELETED",
  memberAdded = "MEMBER_ADDED",
  memberRemoved = "MEMBER_REMOVED",
  schemaCreated = "SCHEMA_CREATED",
  schemaUpdated = "SCHEMA_UPDATED",
  schemaDeleted = "SCHEMA_DELETED",
  policyCreated = "PASSWORD_POLICY_CREATED",
  policyUpdated = "PASSWORD_POLICY_UPDATED",
  policyDeleted = "PASSWORD_POLICY_DELETED",
  apiClientCreated = "API_CLIENT_CREATED",
  apiClientUpdated = "API_CLIENT_UPDATED",
  apiClientDeleted = "API_CLIENT_DELETED",
  apiClientRevoked = "API_CLIENT_REVOKED",
  apiClientReactivated = "API_CLIENT_REACTIVATED",
  apiClientSecretRotated = "API_CLIENT_SECRET_ROTATED",
  apiClientExpired = "API_CLIENT_EXPIRED",
  auditPurged = "AUDIT_PURGED",
  custom = "CUSTOM",
}

///
unittest {
  assert(enumText(AuditEventType.loginFailure) == "LOGIN_FAILURE");
  assert(parseEnum!AuditEventType("LOGIN_FAILURE", AuditEventType.custom) == AuditEventType.loginFailure);
  assert(parseEnum!AuditEventType("loginFailure", AuditEventType.custom) == AuditEventType.loginFailure);
}
