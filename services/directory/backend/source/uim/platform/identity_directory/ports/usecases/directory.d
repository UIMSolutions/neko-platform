/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.ports.usecases.directory;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Users: lifecycle (active ⇄ inactive, locked ⇄ active, staged → active),
/// credentials and sign-in. Deletion removes the user from all groups.
interface IManageUsersUseCase : IManageResource!(DirectoryUser, DirectoryUserId, CreateUserRequest, UpdateUserRequest) {
  UsecaseResult activate(TenantId tenantId, DirectoryUserId id, UserId actor);
  UsecaseResult deactivate(TenantId tenantId, DirectoryUserId id, UserId actor);
  UsecaseResult lock(TenantId tenantId, DirectoryUserId id, UserId actor);
  UsecaseResult unlock(TenantId tenantId, DirectoryUserId id, UserId actor);
  /// Administrative password reset (policy and history are checked).
  UsecaseResult setPassword(TenantId tenantId, DirectoryUserId id, string password, bool mustChange, UserId actor);
  /// Self-service password change (the current password is verified).
  UsecaseResult changePassword(TenantId tenantId, DirectoryUserId id, string currentPassword, string newPassword, UserId actor);
  /// Verify a password and record the sign-in (failed attempts lead to lockout). code 401 on failure.
  UsecaseResult authenticate(TenantId tenantId, DirectoryUserId id, string password, string ipAddress, UserId actor);
  /// The user with this user name (case-insensitive); DirectoryUser.init if none.
  DirectoryUser findByUserName(TenantId tenantId, string userName);
}

/// Groups: direct members (users, nested groups) or a membership rule (dynamic groups).
interface IManageGroupsUseCase : IManageResource!(DirectoryGroup, GroupId, CreateGroupRequest, UpdateGroupRequest) {
  /// `member` is an id, user name or group display name; memberType "" detects the kind.
  UsecaseResult addMember(TenantId tenantId, GroupId id, string member, string memberType, UserId actor);
  UsecaseResult removeMember(TenantId tenantId, GroupId id, string member, UserId actor);
  /// Recompute the members of a dynamic group from its rule.
  UsecaseResult evaluate(TenantId tenantId, GroupId id, UserId actor);
}

/// Custom schemas extending users and groups.
interface IManageSchemasUseCase : IManageResource!(CustomSchema, SchemaId, CreateSchemaRequest, UpdateSchemaRequest) {
}

/// Password policies (one default per tenant).
interface IManagePasswordPoliciesUseCase : IManageResource!(PasswordPolicy, PasswordPolicyId,
    CreatePasswordPolicyRequest, UpdatePasswordPolicyRequest) {
  UsecaseResult makeDefault(TenantId tenantId, PasswordPolicyId id, UserId actor);
  /// The policy that applies to a user (its named policy or the tenant default).
  PasswordPolicy policyFor(TenantId tenantId, string policyName);
}

/// API clients (technical users with client credentials).
interface IManageApiClientsUseCase : IManageResource!(ApiClient, ApiClientId, CreateApiClientRequest, UpdateApiClientRequest) {
  /// New secret; returned once in UsecaseResult.data["clientSecret"].
  UsecaseResult rotateSecret(TenantId tenantId, ApiClientId id, UserId actor);
  UsecaseResult revoke(TenantId tenantId, ApiClientId id, UserId actor);
  UsecaseResult reactivate(TenantId tenantId, ApiClientId id, UserId actor);
  /// Verify a client secret (records the use). code 401 on failure.
  UsecaseResult verify(TenantId tenantId, ApiClientId id, string secret, UserId actor);
}

/// The audit log. Entries are immutable; old entries are purged by housekeeping.
interface IAuditLogUseCase : IManageResource!(AuditEvent, AuditEventId, CreateAuditEventRequest, UpdateAuditEventRequest) {
  /// Remove entries older than `before` (std time). Returns the number removed in `id`.
  UsecaseResult purge(TenantId tenantId, long before, UserId actor);
}

/// Time driven transitions: automatic unlock, password expiry, client expiry,
/// dynamic group evaluation and audit retention.
interface IHousekeepingUseCase {
  HousekeepingReport run(TenantId tenantId);
}
