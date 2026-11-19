/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module uim.platform.identity_directory.application.usecases.manage.users;

import uim.platform.identity_directory;

mixin(ShowModule!());

@safe:

/// Interactor: users. User names are unique per tenant (case-insensitive),
/// extension attributes follow the custom schemas, passwords follow the
/// user's password policy (including history and lockout).
class ManageUsersUseCase
  : ResourceUseCase!(DirectoryUser, DirectoryUserId, CreateUserRequest, UpdateUserRequest),
  IManageUsersUseCase {

  protected ICredentialService credentials;
  protected MembershipService memberships;

  this(DirectoryRepositories repos, ICredentialService credentials, MembershipService memberships,
      IDirectoryEventPublisher publisher, AuditTrail audit, NowFn clock) {
    super(repos, repos.users, publisher, audit, clock, "User", "identity.user",
      AuditKinds(AuditEventType.userCreated, AuditEventType.userUpdated, AuditEventType.userDeleted));
    this.credentials = credentials;
    this.memberships = memberships;
  }

  DirectoryUser findByUserName(TenantId tenantId, string userName) {
    return repo.findByName(tenantId, userName);
  }

  // ── create / update ────────────────────────────────────────────────────

  override protected DirectoryUser build(CreateUserRequest r) {
    auto user = DirectoryUser(r.tenantId);
    assignMatching(user, r.spec, ["status"]);
    validate(r.spec.status != UserStatus.locked, "A new user cannot be locked");
    user.status = r.spec.status;
    check(user, DirectoryUser.init);
    if (r.spec.password.length > 0)
      applyPassword(user, r.spec.password, r.spec.mustChangePassword);
    return user;
  }

  override protected void apply(ref DirectoryUser user, UserSpec spec) {
    auto before = user;
    assignMatching(user, spec, ["status"]);
    if (spec.status != user.status)
      changeStatus(user, spec.status);
    check(user, before);
    if (spec.password.length > 0)
      applyPassword(user, spec.password, spec.mustChangePassword);
  }

  protected void check(ref DirectoryUser user, const DirectoryUser before) {
    user.userName = user.userName.strip;
    validate(isUserName(user.userName), "User name '" ~ user.userName
        ~ "' must be 1-256 letters, digits or . _ - @ + '");
    ensureUnique(repo.findByName(user.tenantId, user.userName), user);
    user.externalId = user.externalId.strip;
    if (user.externalId.length > 0) {
      auto ext = user.externalId;
      auto id = user.id;
      ensureState(repo.findMatching(user.tenantId, (const DirectoryUser o) => o.id != id && o.externalId == ext).length == 0,
        "External ID '" ~ ext ~ "' is already used by another user");
    }
    validate(user.displayName.length <= 256, "Display name must not exceed 256 characters");
    validate(isOptionalUrl(user.profileUrl), "Profile URL '" ~ user.profileUrl ~ "' must be an http(s) URL");
    user.emails = normalizeEmails(user.emails);
    user.phoneNumbers = normalizePhoneNumbers(user.phoneNumbers);
    user.addresses = normalizeAddresses(user.addresses);
    user.passwordPolicy = user.passwordPolicy.strip;
    if (user.passwordPolicy.length > 0) {
      auto policy = repos.policies.findByName(user.tenantId, user.passwordPolicy);
      ensureFound(!policy.isNull, "Password policy '" ~ user.passwordPolicy ~ "' not found");
      user.passwordPolicy = policy.name;
    }
    auto schemas = repos.schemas.findByTenant(user.tenantId);
    user.extendedAttributes = checkExtensions(user.extendedAttributes, schemas, SchemaTarget.user,
      before.extendedAttributes);
    ensureUniqueExtensions(user, schemas);
  }

  /// Attributes with uniqueness server/global must not be shared by two users.
  protected void ensureUniqueExtensions(const DirectoryUser user, const CustomSchema[] schemas) {
    foreach (ext; user.extendedAttributes) {
      auto def = schemaFor(schemas, ext.schema).attributeOf(ext.name);
      if (def.uniqueness == Uniqueness.none)
        continue;
      auto id = user.id;
      auto clash = repo.findMatching(user.tenantId, (const DirectoryUser o) => o.id != id
          && o.extendedAttributes.any!(x => x.schema == ext.schema && x.name == ext.name && sameName(x.value, ext.value)));
      ensureState(clash.length == 0, ext.name ~ " '" ~ ext.value ~ "' is already used by user '"
          ~ (clash.length ? clash[0].userName : "") ~ "'");
    }
  }

  protected void changeStatus(ref DirectoryUser user, UserStatus status) {
    if (status == UserStatus.locked)
      lockUser(user, clock(), 0);
    else if (user.status == UserStatus.locked) {
      unlockUser(user);
      user.status = status;
    } else
      user.status = status;
  }

  override protected void afterChange(DirectoryUser user, DirectoryUser before) {
    if (!before.isNull && before.userName != user.userName)
      memberships.renameEverywhere(user.tenantId, user.id.value, user.userName);
    memberships.refreshDynamicGroups(user.tenantId);
    memberships.syncUsers(user.tenantId);
  }

  override protected void afterRemove(DirectoryUser user) {
    memberships.removeEverywhere(user.tenantId, user.id.value);
    memberships.refreshDynamicGroups(user.tenantId);
    memberships.syncUsers(user.tenantId);
  }

  // ── lifecycle ──────────────────────────────────────────────────────────

  UsecaseResult activate(TenantId tenantId, DirectoryUserId id, UserId actor) {
    return transition(tenantId, id, actor, "activated", AuditEventType.userActivated, (ref DirectoryUser u) {
      ensureState(u.status != UserStatus.active, "User '" ~ u.userName ~ "' is already active");
      ensureState(u.status != UserStatus.locked, "User '" ~ u.userName ~ "' is locked — unlock it instead");
      u.status = UserStatus.active;
    });
  }

  UsecaseResult deactivate(TenantId tenantId, DirectoryUserId id, UserId actor) {
    return transition(tenantId, id, actor, "deactivated", AuditEventType.userDeactivated, (ref DirectoryUser u) {
      ensureState(u.status != UserStatus.inactive, "User '" ~ u.userName ~ "' is already inactive");
      u.status = UserStatus.inactive;
    });
  }

  UsecaseResult lock(TenantId tenantId, DirectoryUserId id, UserId actor) {
    return transition(tenantId, id, actor, "locked", AuditEventType.userLocked, (ref DirectoryUser u) {
      ensureState(u.status != UserStatus.locked, "User '" ~ u.userName ~ "' is already locked");
      lockUser(u, clock(), 0);
    });
  }

  UsecaseResult unlock(TenantId tenantId, DirectoryUserId id, UserId actor) {
    return transition(tenantId, id, actor, "unlocked", AuditEventType.userUnlocked, (ref DirectoryUser u) {
      ensureState(u.status == UserStatus.locked, "User '" ~ u.userName ~ "' is not locked");
      unlockUser(u);
    });
  }

  // ── credentials ────────────────────────────────────────────────────────

  UsecaseResult setPassword(TenantId tenantId, DirectoryUserId id, string password, bool mustChange, UserId actor) {
    return transition(tenantId, id, actor, "password reset", AuditEventType.passwordReset, (ref DirectoryUser u) {
      validate(password.length > 0, "password is required");
      applyPassword(u, password, mustChange);
    });
  }

  UsecaseResult changePassword(TenantId tenantId, DirectoryUserId id, string currentPassword, string newPassword, UserId actor) {
    return transition(tenantId, id, actor, "password changed", AuditEventType.passwordChanged, (ref DirectoryUser u) {
      validate(newPassword.length > 0, "newPassword is required");
      if (u.passwordSet && !credentials.verifySecret(currentPassword, u.passwordHash))
        throw new DirectoryAuthenticationException("The current password of '" ~ u.userName ~ "' is not correct");
      applyPassword(u, newPassword, false);
    });
  }

  UsecaseResult authenticate(TenantId tenantId, DirectoryUserId id, string password, string ipAddress, UserId actor) {
    auto user = repo.findById(tenantId, id);
    if (user.isNull)
      return UsecaseResult(false, "", "User '" ~ id.value ~ "' not found", 404);
    auto now = clock();
    auto policy = policyFor(tenantId, user.passwordPolicy);
    auto ip = ipAddress.length ? [KeyValue("ipAddress", ipAddress)] : null;

    if (isUnlockDue(user, now)) {
      unlockUser(user);
      record(user, AuditEventType.userUnlocked, UserId("system"), "unlocked (lockout expired)");
    }
    if (!user.status.canSignIn) {
      record(user, AuditEventType.loginFailure, actor, "sign-in rejected: account " ~ enumText(user.status),
        AuditOutcome.failure, ip);
      return UsecaseResult(false, "", "User '" ~ user.userName ~ "' is " ~ enumText(user.status), 401);
    }
    if (!user.passwordSet || !credentials.verifySecret(password, user.passwordHash)) {
      auto locked = registerFailedLogin(user, policy, now);
      repo.update(user);
      record(user, AuditEventType.loginFailure, actor, "sign-in failed", AuditOutcome.failure,
        ip ~ KeyValue("failedAttempts", user.failedLoginAttempts.to!string));
      if (locked) {
        record(user, AuditEventType.userLocked, UserId("system"), "locked after "
            ~ user.failedLoginAttempts.to!string ~ " failed sign-ins");
        return UsecaseResult(false, "", "Invalid credentials — user '" ~ user.userName ~ "' is now locked", 401);
      }
      return UsecaseResult(false, "", "Invalid credentials", 401);
    }

    registerSuccessfulLogin(user, now);
    if (credentials.needsRehash(user.passwordHash))
      user.passwordHash = credentials.hashSecret(password);
    auto expired = isPasswordExpired(policy, user.passwordChangedAt, now);
    if (expired)
      user.mustChangePassword = true;
    repo.update(user);
    record(user, AuditEventType.loginSuccess, actor, "signed in", AuditOutcome.success, ip);
    auto data = Json.emptyObject
      .set("mustChangePassword", user.mustChangePassword)
      .set("passwordExpired", expired);
    return succeeded(user.id.value, user.mustChangePassword
        ? "User '" ~ user.userName ~ "' signed in — the password must be changed"
        : "User '" ~ user.userName ~ "' signed in", data);
  }

  /// Validate a new password against policy and history, then store its hash.
  protected void applyPassword(ref DirectoryUser user, string password, bool mustChange) {
    auto policy = policyFor(user.tenantId, user.passwordPolicy);
    validatePassword(password, policy, user.userName);
    auto recent = (user.passwordSet ? [user.passwordHash] : null) ~ user.passwordHistory;
    if (recent.length > policy.historyCount)
      recent = recent[0 .. policy.historyCount];
    validate(!recent.any!(h => credentials.verifySecret(password, h)),
      "Password was used recently — policy '" ~ policy.name ~ "' remembers " ~ policy.historyCount.to!string ~ " passwords");
    if (user.passwordSet && policy.historyCount > 0)
      user.passwordHistory = ([user.passwordHash] ~ user.passwordHistory)[0 .. min(policy.historyCount, user.passwordHistory.length + 1)];
    user.passwordHash = credentials.hashSecret(password);
    user.passwordSet = true;
    user.passwordChangedAt = clock();
    user.mustChangePassword = mustChange;
  }

  /// The user's policy: its named policy, else the tenant default, else the built-in rules.
  protected PasswordPolicy policyFor(TenantId tenantId, string name) {
    if (name.length > 0) {
      auto p = repos.policies.findByName(tenantId, name);
      if (!p.isNull)
        return p;
    }
    auto defaults = repos.policies.findMatching(tenantId, (const PasswordPolicy p) => p.isDefault);
    if (defaults.length > 0)
      return defaults[0];
    PasswordPolicy builtIn;
    builtIn.name = "built-in";
    builtIn.expiryDays = 0;
    return builtIn;
  }
}
