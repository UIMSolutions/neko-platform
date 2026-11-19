/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.infrastructure.container;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Dependency injection container — wires domain, application and persistence.
/// Presentation adapters (REST, OData, SCIM, CLI, GUI) are created by the entry
/// points (app.d, cli.d, gui.d) on top of this container and only see `ports`.
class Container {
  DirectoryConfig config;

  // ── Driven adapters ───────────────────────────────────────────────────
  ISnapshotStorage storage; // null in "memory" mode
  DirectoryRepositories repositories;
  IDirectoryEventPublisher publisher;
  ICredentialService credentials;

  // ── Application services ──────────────────────────────────────────────
  AuditTrail audit;
  MembershipService memberships;

  // ── Driving ports ─────────────────────────────────────────────────────
  DirectoryPorts ports;

  this(DirectoryConfig config, NowFn clock = null) {
    this.config = config;
    if (clock is null)
      clock = () => nowStdTime();
    wirePersistence();
    wireApplication(clock);
  }

  protected void wirePersistence() {
    if (config.usesFileStorage)
      storage = new JsonFileSnapshotStorage(config.dataDir);

    auto repo(TEntity, TId)(string collection) {
      ITenantStore!(TEntity, TId) s = storage is null
        ? new TenantStore!(TEntity, TId)()
        : new SnapshotTenantStore!(TEntity, TId, RecordMapper!TEntity)(storage, collection);
      return new DirectoryRepository!(TEntity, TId)(s);
    }

    alias C = DirectoryCollections;
    with (repositories) {
      users = repo!(DirectoryUser, DirectoryUserId)(C.users);
      groups = repo!(DirectoryGroup, GroupId)(C.groups);
      schemas = repo!(CustomSchema, SchemaId)(C.schemas);
      policies = repo!(PasswordPolicy, PasswordPolicyId)(C.policies);
      apiClients = repo!(ApiClient, ApiClientId)(C.apiClients);
      auditEvents = repo!(AuditEvent, AuditEventId)(C.auditEvents);
    }
    if (config.eventWebhookUrl.length > 0)
      publisher = new WebhookEventPublisher(config.eventWebhookUrl);
    else
      publisher = new LogEventPublisher();
    credentials = new Pbkdf2CredentialService(cast(uint) max(config.passwordHashIterations, 1000));
  }

  protected void wireApplication(NowFn clock) {
    auto r = repositories;
    audit = new AuditTrail(r.auditEvents, clock);
    memberships = new MembershipService(r, clock);
    with (ports) {
      users = new ManageUsersUseCase(r, credentials, memberships, publisher, audit, clock);
      groups = new ManageGroupsUseCase(r, memberships, publisher, audit, clock);
      schemas = new ManageSchemasUseCase(r, publisher, audit, clock);
      passwordPolicies = new ManagePasswordPoliciesUseCase(r, publisher, audit, clock);
      apiClients = new ManageApiClientsUseCase(r, credentials, publisher, audit, clock);
      auditLog = new AuditLogUseCase(r, audit);
      housekeeping = new HousekeepingUseCase(r, memberships, auditLog, audit, clock, config.auditRetentionDays);
      statistics = new DirectoryStatisticsService(r, clock);
      seeder = new DirectorySeedService(r, audit);
    }
  }
}

/// Build the full dependency graph.
Container buildContainer(DirectoryConfig config, NowFn clock = null) {
  return new Container(config, clock);
}

/// A memory-only configuration with a cheap hash work factor (tests).
DirectoryConfig testConfig(string tenant = "default") {
  DirectoryConfig cfg;
  cfg.storage = "memory";
  cfg.passwordHashIterations = 1000;
  cfg.defaultTenant = tenant;
  return cfg;
}

///
unittest {
  mixin(ShowTest!("Container — end-to-end scenario"));

  long offset; // simulated time travel for lockout / expiry / housekeeping
  auto c = buildContainer(testConfig, () => nowStdTime() + offset);
  auto p = c.ports;
  auto t = TenantId("t1");
  auto admin = UserId("admin");

  // ── seed: policies + enterprise schema ────────────────────────────────
  auto seeded = p.seeder.seed(t, admin);
  assert(seeded.created == 4 && seeded.skipped == 0, seeded.items.join(", "));
  assert(p.seeder.seed(t, admin).created == 0); // idempotent
  auto standard = p.passwordPolicies.list(t).filter!(x => x.name == "Standard").front;
  assert(standard.isDefault && standard.strength == PasswordStrength.standard);
  assert(p.passwordPolicies.remove(t, standard.id, admin).code == 409); // predefined
  auto enterprise = p.schemas.list(t).front;
  assert(enterprise.urn == enterpriseUserUrn);

  // ── users: validation, uniqueness, extensions, password policy ────────
  CreateUserRequest ur;
  ur.tenantId = t;
  ur.actor = admin;
  ur.spec.userName = "jane.doe";
  ur.spec.givenName = "Jane";
  ur.spec.familyName = "Doe";
  ur.spec.title = "Sales Manager";
  ur.spec.emails = [Email("jane@example.com")];
  ur.spec.extendedAttributes = [ExtendedAttribute("Enterprise User", "employeeNumber", "1001"),
    ExtendedAttribute("Enterprise User", "department", "Sales")];
  ur.spec.password = "weak";
  assert(p.users.create(ur).code == 422); // password policy
  ur.spec.password = "Welcome2026";
  auto janeResult = p.users.create(ur);
  assert(janeResult.isSuccess, janeResult.message);
  auto janeId = DirectoryUserId(janeResult.id);
  auto jane = p.users.get(t, janeId);
  assert(jane.passwordSet && jane.passwordHash.startsWith("pbkdf2-sha256$") && jane.emails[0].primary);
  assert(jane.extendedAttributes[0].schema == enterpriseUserUrn);
  assert(p.users.create(ur).code == 409); // duplicate user name
  ur.spec.userName = "JANE.DOE";
  assert(p.users.create(ur).code == 409); // case-insensitive
  ur.spec.userName = "john";
  assert(p.users.create(ur).code == 409, "employeeNumber is unique"); // uniqueness server
  ur.spec.extendedAttributes = [ExtendedAttribute("Enterprise User", "costCenter", "C1")];
  ur.spec.emails = [Email("john@")];
  assert(p.users.create(ur).code == 422); // e-mail
  ur.spec.emails = null;
  ur.spec.extendedAttributes = [ExtendedAttribute("Nope", "x", "y")];
  assert(p.users.create(ur).code == 422); // unknown schema
  ur.spec.extendedAttributes = null;
  ur.spec.userType = UserType.contractor;
  ur.spec.title = "Engineer";
  ur.spec.password = "";
  auto johnId = DirectoryUserId(p.users.create(ur).id);

  // ── sign-in, lockout, automatic unlock, password history ──────────────
  assert(p.users.authenticate(t, janeId, "Welcome2026", "10.0.0.1", admin).isSuccess);
  assert(p.users.get(t, janeId).lastLoginAt > 0);
  foreach (i; 0 .. 4)
    assert(p.users.authenticate(t, janeId, "wrong", "", admin).code == 401);
  auto lockedOut = p.users.authenticate(t, janeId, "wrong", "", admin);
  assert(lockedOut.code == 401 && lockedOut.message.canFind("locked"), lockedOut.message);
  assert(p.users.get(t, janeId).status == UserStatus.locked);
  assert(p.users.authenticate(t, janeId, "Welcome2026", "", admin).code == 401); // locked
  assert(p.users.authenticate(t, johnId, "anything", "", admin).code == 401); // no password
  offset = 31 * 600_000_000L; // 31 minutes later
  assert(p.housekeeping.run(t).changes.canFind("user 'jane.doe' unlocked (lockout expired)"));
  assert(p.users.get(t, janeId).status == UserStatus.active);
  assert(p.users.changePassword(t, janeId, "nope", "Spring2027x", admin).code == 401);
  assert(p.users.changePassword(t, janeId, "Welcome2026", "Welcome2026", admin).code == 422); // history
  assert(p.users.changePassword(t, janeId, "Welcome2026", "Spring2027x", admin).isSuccess);
  assert(p.users.setPassword(t, janeId, "Welcome2026", false, admin).code == 422); // still in history
  assert(p.users.get(t, janeId).passwordHistory.length == 1);

  // ── groups: standard, nested (no cycles), dynamic rules ───────────────
  CreateGroupRequest gr;
  gr.tenantId = t;
  gr.actor = admin;
  gr.spec.displayName = "Sales";
  gr.spec.members = [GroupMember("jane.doe")]; // by user name
  auto salesId = GroupId(p.groups.create(gr).id);
  assert(p.users.get(t, janeId).groups == ["Sales"]);
  assert(p.groups.create(gr).code == 409);
  gr.spec.displayName = "EMEA";
  gr.spec.groupType = GroupType.nested;
  gr.spec.members = null;
  auto emeaId = GroupId(p.groups.create(gr).id);
  assert(p.groups.addMember(t, salesId, "EMEA", "", admin).code == 409); // standard group: no groups
  assert(p.groups.addMember(t, emeaId, "Sales", "group", admin).isSuccess);
  assert(p.users.get(t, janeId).inheritedGroups == ["EMEA"]);
  UpdateGroupRequest gu;
  gu.tenantId = t;
  gu.actor = admin;
  gu.id = salesId;
  gu.spec.displayName = "Sales";
  gu.spec.groupType = GroupType.nested;
  gu.spec.members = [GroupMember(janeId.value), GroupMember(emeaId.value, MemberType.group)];
  assert(p.groups.update(gu).code == 409); // EMEA ⊃ Sales ⊃ EMEA
  assert(p.groups.addMember(t, salesId, "nobody", "", admin).code == 404);
  assert(p.groups.addMember(t, salesId, "john", "user", admin).isSuccess);
  assert(p.groups.addMember(t, salesId, "john", "", admin).code == 409);
  assert(p.groups.removeMember(t, salesId, "john", admin).isSuccess);

  gr.spec.displayName = "Contractors";
  gr.spec.groupType = GroupType.dynamic;
  gr.spec.membershipRule = `userType eq "contractor"`;
  auto dynId = GroupId(p.groups.create(gr).id);
  assert(p.groups.get(t, dynId).members.map!(m => m.display).array == ["john"]);
  assert(p.groups.addMember(t, dynId, "jane.doe", "", admin).code == 409);
  gr.spec.displayName = "Broken";
  gr.spec.membershipRule = `userType eq`;
  assert(p.groups.create(gr).code == 422);
  UpdateUserRequest uu;
  uu.tenantId = t;
  uu.actor = admin;
  uu.id = janeId;
  uu.spec = decode!UserSpec(encode(p.users.get(t, janeId)));
  uu.spec.userType = UserType.contractor;
  uu.spec.userName = "jane";
  assert(p.users.update(uu).isSuccess);
  assert(p.groups.get(t, dynId).members.length == 2); // rule re-evaluated
  assert(p.groups.get(t, salesId).members[0].display == "jane"); // rename propagated
  gr.spec.displayName = "Sales Contractors";
  gr.spec.membershipRule = `userType eq "contractor" and title co "sales"`;
  assert(p.groups.get(t, GroupId(p.groups.create(gr).id)).members.length == 1);

  // ── schemas: in use, required attributes ──────────────────────────────
  assert(p.schemas.remove(t, enterprise.id, admin).code == 409); // predefined
  CreateSchemaRequest sr;
  sr.tenantId = t;
  sr.actor = admin;
  sr.spec.urn = "urn:uim:schemas:extension:hr:1.0:User";
  sr.spec.name = "HR";
  sr.spec.attributes = [SchemaAttribute("grade", "", AttributeType.integer)];
  auto hrId = SchemaId(p.schemas.create(sr).id);
  assert(p.schemas.create(sr).code == 409);
  uu.spec = decode!UserSpec(encode(p.users.get(t, janeId)));
  uu.spec.extendedAttributes ~= ExtendedAttribute("HR", "grade", "7");
  assert(p.users.update(uu).isSuccess);
  assert(p.schemas.remove(t, hrId, admin).code == 409); // in use
  UpdateSchemaRequest su;
  su.tenantId = t;
  su.actor = admin;
  su.id = hrId;
  su.spec = sr.spec;
  su.spec.attributes = [SchemaAttribute("level")];
  assert(p.schemas.update(su).code == 409); // "grade" in use

  // ── password policies ─────────────────────────────────────────────────
  CreatePasswordPolicyRequest pr;
  pr.tenantId = t;
  pr.actor = admin;
  pr.spec.name = "Kiosk";
  pr.spec.minLength = 20;
  pr.spec.maxLength = 10;
  assert(p.passwordPolicies.create(pr).code == 422);
  pr.spec.maxLength = 64;
  pr.spec.expiryDays = 1;
  pr.spec.warningDays = 0;
  auto kioskId = PasswordPolicyId(p.passwordPolicies.create(pr).id);
  assert(!p.passwordPolicies.get(t, kioskId).isDefault);
  assert(p.passwordPolicies.makeDefault(t, kioskId, admin).isSuccess);
  assert(!p.passwordPolicies.get(t, standard.id).isDefault);
  assert(p.passwordPolicies.remove(t, kioskId, admin).code == 409); // default
  assert(p.passwordPolicies.makeDefault(t, standard.id, admin).isSuccess);
  uu.spec = decode!UserSpec(encode(p.users.get(t, janeId)));
  uu.spec.passwordPolicy = "kiosk";
  uu.spec.password = "Short1abc";
  assert(p.users.update(uu).code == 422); // 20 characters needed
  uu.spec.password = "LongEnoughPassword2026";
  assert(p.users.update(uu).isSuccess);
  assert(p.passwordPolicies.remove(t, kioskId, admin).code == 409); // used by jane

  // ── API clients: secret once, verify, revoke, expiry ──────────────────
  CreateApiClientRequest cr;
  cr.tenantId = t;
  cr.actor = admin;
  cr.spec.name = "Provisioning";
  cr.spec.scopes = ["directory.read", "directory.write", "directory.read"];
  auto created = p.apiClients.create(cr);
  assert(created.isSuccess, created.message);
  auto secret = created.data["clientSecret"].get!string;
  auto clientId = ApiClientId(created.id);
  auto client = p.apiClients.get(t, clientId);
  assert(client.scopes.length == 2 && client.secretHash != secret && client.secretHint == "…" ~ secret[$ - 4 .. $]);
  assert(p.apiClients.verify(t, clientId, secret, admin).isSuccess);
  assert(p.apiClients.verify(t, clientId, "wrong", admin).code == 401);
  auto rotated = p.apiClients.rotateSecret(t, clientId, admin);
  assert(p.apiClients.verify(t, clientId, secret, admin).code == 401);
  assert(p.apiClients.verify(t, clientId, rotated.data["clientSecret"].get!string, admin).isSuccess);
  assert(p.apiClients.revoke(t, clientId, admin).isSuccess);
  assert(p.apiClients.verify(t, clientId, rotated.data["clientSecret"].get!string, admin).code == 401);
  cr.spec.name = "Reporting";
  cr.spec.expiresAt = nowStdTime() + offset - 1;
  assert(p.apiClients.create(cr).code == 422); // in the past
  cr.spec.expiresAt = nowStdTime() + offset + stdTimeDay;
  auto reportingId = ApiClientId(p.apiClients.create(cr).id);

  // ── housekeeping two days later: password + client expiry ─────────────
  offset += 2 * stdTimeDay;
  auto hk = p.housekeeping.run(t);
  assert(hk.changes.canFind("password of 'jane' expired"), hk.changes.join("; ")); // kiosk: 1 day
  assert(hk.changes.canFind("API client 'Reporting' expired"), hk.changes.join("; "));
  assert(p.users.get(t, janeId).mustChangePassword);
  assert(p.apiClients.reactivate(t, reportingId, admin).code == 409); // expired

  // ── audit trail ───────────────────────────────────────────────────────
  auto log = p.auditLog.list(t);
  assert(log.any!(e => e.eventType == AuditEventType.userLocked));
  assert(log.any!(e => e.eventType == AuditEventType.loginFailure && e.outcome == AuditOutcome.failure));
  assert(log.any!(e => e.eventType == AuditEventType.apiClientSecretRotated && e.targetType == "ApiClient"));
  assert(p.auditLog.remove(t, log[0].id, admin).code == 409); // immutable
  CreateAuditEventRequest ar;
  ar.tenantId = t;
  ar.actor = admin;
  ar.spec.eventType = AuditEventType.loginSuccess;
  ar.spec.targetName = "jane";
  assert(p.auditLog.create(ar).isSuccess);

  // ── statistics ────────────────────────────────────────────────────────
  auto s = p.statistics.statistics(t);
  assert(s.users == 2 && s.usersActive == 2 && s.usersMustChangePassword == 1, encode(s).toString);
  assert(s.groups == 4 && s.groupsNested == 1 && s.groupsDynamic == 2 && s.schemas == 2 && s.passwordPolicies == 4);
  assert(s.apiClients == 2 && s.apiClientsActive == 0 && s.auditEvents > 20 && s.lastLoginAt > 0);

  // ── deletion cascades ─────────────────────────────────────────────────
  assert(p.users.remove(t, janeId, admin).isSuccess);
  assert(p.groups.get(t, salesId).members.length == 0);
  assert(p.groups.get(t, dynId).members.map!(m => m.display).array == ["john"]);
  assert(p.groups.remove(t, salesId, admin).isSuccess);
  assert(p.groups.get(t, emeaId).members.length == 0);
  assert(p.schemas.remove(t, hrId, admin).isSuccess); // no longer in use
  assert(p.passwordPolicies.remove(t, kioskId, admin).isSuccess);

  // ── audit retention ───────────────────────────────────────────────────
  offset += 400 * stdTimeDay;
  auto purge = p.housekeeping.run(t);
  assert(purge.changes.any!(x => x.canFind("audit event(s) purged")), purge.changes.join("; "));
  assert(p.auditLog.list(t).length < 10);
}
