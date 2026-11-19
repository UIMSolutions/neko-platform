/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.persistence.repositories.directory;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Generic repository of a directory aggregate on top of a tenant store
/// (in memory or JSON snapshots, see the container).
class DirectoryRepository(TEntity, TId) : TenantRepository!(TEntity, TId), IDirectoryRepository!(TEntity, TId) {
  this() {
    super();
  }

  this(ITenantStore!(TEntity, TId) store) {
    super(store);
  }

  TEntity findByName(TenantId tenantId, string name) {
    foreach (e; findByTenant(tenantId))
      if (sameName(nameOf(e), name))
        return e;
    return TEntity.init;
  }

  TEntity[] findMatching(TenantId tenantId, scope bool delegate(const TEntity) @safe specification) {
    TEntity[] result;
    foreach (e; findByTenant(tenantId))
      if (specification(e))
        result ~= e;
    return result;
  }
}

alias UserRepository = DirectoryRepository!(DirectoryUser, DirectoryUserId);
alias GroupRepository = DirectoryRepository!(DirectoryGroup, GroupId);
alias SchemaRepository = DirectoryRepository!(CustomSchema, SchemaId);
alias PasswordPolicyRepository = DirectoryRepository!(PasswordPolicy, PasswordPolicyId);
alias ApiClientRepository = DirectoryRepository!(ApiClient, ApiClientId);
alias AuditRepository = DirectoryRepository!(AuditEvent, AuditEventId);

///
unittest {
  mixin(ShowTest!("DirectoryRepository"));

  assert(tenantRepositoryTest(new UserRepository()));
  assert(tenantRepositoryTest(new GroupRepository()));

  auto t = TenantId("t1");
  auto repo = new UserRepository();
  auto u = DirectoryUser(t);
  u.userName = "Jane.Doe";
  repo.save(u);
  assert(!repo.findByName(t, "jane.doe").isNull && repo.findByName(t, "bob").isNull);
  assert(repo.findMatching(t, (const DirectoryUser x) => x.userName.startsWith("Jane")).length == 1);
  assert(repo.findByName(TenantId("t2"), "jane.doe").isNull);
}
