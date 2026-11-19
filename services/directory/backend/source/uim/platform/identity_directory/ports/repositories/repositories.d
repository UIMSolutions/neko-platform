/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.ports.repositories.repositories;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Persistence port of every directory aggregate: the tenant repository plus
/// lookups by display name and by specification.
interface IDirectoryRepository(TEntity, TId) : ITenantRepository!(TEntity, TId) {
  /// First aggregate whose display name (see nameOf) equals `name`, ignoring case (TEntity.init if none).
  TEntity findByName(TenantId tenantId, string name);
  /// Aggregates satisfying a specification.
  TEntity[] findMatching(TenantId tenantId, scope bool delegate(const TEntity) @safe specification);
}

alias IUserRepository = IDirectoryRepository!(DirectoryUser, DirectoryUserId);
alias IGroupRepository = IDirectoryRepository!(DirectoryGroup, GroupId);
alias ISchemaRepository = IDirectoryRepository!(CustomSchema, SchemaId);
alias IPasswordPolicyRepository = IDirectoryRepository!(PasswordPolicy, PasswordPolicyId);
alias IApiClientRepository = IDirectoryRepository!(ApiClient, ApiClientId);
alias IAuditRepository = IDirectoryRepository!(AuditEvent, AuditEventId);

/// All driven persistence ports, handed to the interactors by the container.
struct DirectoryRepositories {
  IUserRepository users;
  IGroupRepository groups;
  ISchemaRepository schemas;
  IPasswordPolicyRepository policies;
  IApiClientRepository apiClients;
  IAuditRepository auditEvents;
}
