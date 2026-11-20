/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web user accounts: sign-in, the first administrator, account management.
module neko.platform.application.usecases.manage_users;

import std.algorithm : count, map, sort;
import std.array : array, join;
import std.string : strip, toLower;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.application.usecases.access;
import neko.platform.ports;

@safe:

class ManageUsersUseCase : IManageUsersUseCase, IAuthenticateUseCase {
  private IUserRepository users;
  private IRoleRepository roles;
  private IPasswordHasher hasher;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  /// Verified for unknown user names, so a failed sign-in takes the same time
  /// whether or not the account exists.
  private string dummyHash;

  this(IUserRepository users, IRoleRepository roles, IPasswordHasher hasher, IEventPublisher events, IClock clock,
      IIdGenerator ids) {
    this.users = users;
    this.roles = roles;
    this.hasher = hasher;
    this.events = events;
    this.clock = clock;
    this.ids = ids;
  }

  // ── IAuthenticateUseCase ────────────────────────────────────────────────

  UserDto authenticate(string userName, string password) {
    UserAccount account;
    bool known;
    try
      known = users.tryGetByName(UserName(userName).value, account);
    catch (ValidationException) {
    }
    auto matches = hasher.verify(password, known ? account.passwordHash : placeholderHash());
    if (!known || !matches || !account.active) {
      emit("user.login.failed", known ? account.id.value : "", userName.strip.toLower, "Sign-in failed");
      throw new AuthenticationException;
    }
    account.recordLogin(clock.now);
    users.save(account);
    emit("user.login", account.id.value, account.userName.value, account.userName.value ~ " signed in");
    return dto(account);
  }

  bool tryActive(string id, out UserDto user) {
    UserAccount account;
    if (id.length == 0 || !users.tryGet(AccountId(id), account) || !account.active)
      return false;
    // Rights are resolved on every request: role changes apply at once.
    user = dto(account);
    return true;
  }

  BootstrapResult ensureAdministrator(string userName, string password) {
    BootstrapResult result;
    if (users.all.length > 0)
      return result;
    if (password.length == 0) {
      password = hasher.randomSecret()[0 .. 20];
      result.generatedPassword = password;
    }
    CreateUserRequest r;
    r.userName = userName.length > 0 ? userName : "admin";
    r.password = password;
    r.displayName = "Administrator";
    r.roles = [adminRole];
    auto created = create(r, "system");
    result.created = true;
    result.userName = created.userName;
    return result;
  }

  // ── IManageUsersUseCase ─────────────────────────────────────────────────

  UserDto[] list() {
    auto all = users.all;
    all.sort!((a, b) => a.userName.value < b.userName.value);
    auto catalogue = roles.all;
    return all.map!(a => a.toDto(catalogue)).array;
  }

  UserDto get(string id) {
    return dto(load(id));
  }

  UserDto create(CreateUserRequest request, string actor) {
    auto name = UserName(request.userName);
    UserAccount existing;
    if (users.tryGetByName(name.value, existing))
      throw new ConflictException("A user named '" ~ name.value ~ "' already exists");
    PasswordPolicy.require(request.password);
    auto assigned = resolveRoles(request.roles.length > 0 ? request.roles : [viewerRole]);

    auto now = clock.now;
    UserAccount account;
    account.id = AccountId(ids.newId);
    account.userName = name;
    account.createdAt = now;
    account.changeProfile(request.displayName, request.email, now);
    account.assignRoles(assigned, now);
    requireCovers(users, roles, actor, rightsOf(account), "assign these roles");
    account.setActive(request.active, now);
    account.changePasswordHash(hasher.hash(request.password), now);
    users.save(account);
    emit("user.created", account.id.value, actor, "Created user " ~ name.value ~ " (roles: "
        ~ account.roles.join(", ") ~ ")");
    return dto(account);
  }

  UserDto update(string id, UpdateUserRequest request, string actor) {
    auto account = load(id);
    requireManageable(account, actor);
    auto now = clock.now;
    account.changeProfile(request.displayName.isNull ? account.displayName : request.displayName.get,
      request.email.isNull ? account.email : request.email.get, now);
    auto wasActiveAdmin = account.isActiveAdmin;
    if (!request.roles.isNull) {
      account.assignRoles(resolveRoles(request.roles.get), now);
      requireCovers(users, roles, actor, rightsOf(account), "assign these roles");
    }
    if (!request.active.isNull)
      account.setActive(request.active.get, now);
    if (wasActiveAdmin && !account.isActiveAdmin)
      requireAnotherActiveAdmin(account, "demote or deactivate");
    users.save(account);
    emit("user.changed", account.id.value, actor, "Changed user " ~ account.userName.value ~ " (roles: "
        ~ account.roles.join(", ") ~ (account.active ? "" : ", inactive") ~ ")");
    return dto(account);
  }

  void resetPassword(string id, string password, string actor) {
    auto account = load(id);
    requireManageable(account, actor);
    PasswordPolicy.require(password);
    account.changePasswordHash(hasher.hash(password), clock.now);
    users.save(account);
    emit("user.password.reset", account.id.value, actor, "Reset the password of " ~ account.userName.value);
  }

  void changeOwnPassword(string id, string currentPassword, string newPassword) {
    auto account = load(id);
    if (!hasher.verify(currentPassword, account.passwordHash))
      throw new ValidationException("The current password is wrong");
    PasswordPolicy.require(newPassword);
    if (newPassword == currentPassword)
      throw new ValidationException("The new password must differ from the current one");
    account.changePasswordHash(hasher.hash(newPassword), clock.now);
    users.save(account);
    emit("user.password.changed", account.id.value, account.userName.value,
      account.userName.value ~ " changed the password");
  }

  void remove(string id, string actor) {
    auto account = load(id);
    if (account.userName.value == actor)
      throw new InvalidStateTransitionException("You cannot remove your own account");
    requireManageable(account, actor);
    if (account.isActiveAdmin)
      requireAnotherActiveAdmin(account, "remove");
    users.remove(account.id);
    emit("user.removed", account.id.value, actor, "Removed user " ~ account.userName.value);
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  private UserDto dto(const UserAccount account) {
    return account.toDto(roles.all);
  }

  private AccessRight[] rightsOf(const UserAccount account) {
    return effectiveRights(account.roles, roles.all);
  }

  /// An account with rights beyond the actor's is out of the actor's reach
  /// (e.g. a user manager cannot reset the password of an administrator).
  private void requireManageable(const UserAccount account, string actor) {
    requireCovers(users, roles, actor, rightsOf(account), "change the account '" ~ account.userName.value ~ "'");
  }

  /// Role names → validated names of existing roles.
  private RoleName[] resolveRoles(const(string)[] names) {
    RoleName[] result;
    foreach (n; names) {
      auto name = RoleName(n);
      Role role;
      if (!roles.tryGet(name.value, role))
        throw new ValidationException("Unknown role '" ~ n ~ "'");
      result ~= name;
    }
    return result;
  }

  private UserAccount load(string id) {
    UserAccount account;
    if (!users.tryGet(AccountId(id), account))
      throw new NotFoundException("User", id);
    return account;
  }

  private void requireAnotherActiveAdmin(const UserAccount account, string action) {
    auto others = users.all.count!(a => a.id != account.id && a.isActiveAdmin);
    if (others == 0)
      throw new InvalidStateTransitionException("Cannot " ~ action ~ " '" ~ account.userName.value
          ~ "': it is the last active administrator");
  }

  private string placeholderHash() {
    if (dummyHash.length == 0)
      dummyHash = hasher.hash(hasher.randomSecret());
    return dummyHash;
  }

  private void emit(string type, string subject, string actor, string message) {
    events.publish(PlatformEvent(type, subject, actor, message, clock.now));
  }
}

version (unittest) {
  import std.typecons : nullable;
  import neko.platform.application.services : FixedClock, SequentialIds;
  import neko.platform.application.usecases.manage_roles : ManageRolesUseCase;
  import std.datetime.date : DateTime;
  import std.datetime.systime : SysTime;
  import std.datetime.timezone : UTC;

  class FakeUsers : IUserRepository {
    UserAccount[string] items;

    UserAccount[] all() {
      return items.values;
    }

    bool tryGet(AccountId id, out UserAccount a) {
      if (auto p = id.value in items) {
        a = *p;
        return true;
      }
      return false;
    }

    bool tryGetByName(string name, out UserAccount a) {
      foreach (item; items)
        if (item.userName.value == name) {
          a = item;
          return true;
        }
      return false;
    }

    void save(UserAccount a) {
      items[a.id.value] = a;
    }

    bool remove(AccountId id) {
      return items.remove(id.value);
    }
  }

  class FakeRoles : IRoleRepository {
    Role[string] items;

    Role[] all() {
      return items.values;
    }

    bool tryGet(string name, out Role r) {
      if (auto p = name in items) {
        r = *p;
        return true;
      }
      return false;
    }

    void save(Role r) {
      items[r.name.value] = r;
    }

    bool remove(string name) {
      return items.remove(name);
    }
  }

  /// Reversible "hash" — fast and deterministic for tests.
  class PlainHasher : IPasswordHasher {
    string hash(string password) {
      return "plain$" ~ password;
    }

    bool verify(string password, string hash) {
      return hash == "plain$" ~ password;
    }

    string randomSecret() {
      return "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG";
    }
  }

  class NoEvents : IEventPublisher {
    PlatformEvent[] published;

    void publish(PlatformEvent e) {
      published ~= e;
    }
  }

  bool fails(E)(scope void delegate() @safe dg) {
    try
      dg();
    catch (E)
      return true;
    return false;
  }

  struct Fixture {
    FakeUsers userRepo;
    FakeRoles roleRepo;
    NoEvents events;
    ManageUsersUseCase users;
    ManageRolesUseCase roles;
  }

  Fixture fixture() {
    Fixture f;
    f.userRepo = new FakeUsers;
    f.roleRepo = new FakeRoles;
    f.events = new NoEvents;
    auto clock = new FixedClock(SysTime(DateTime(2026, 11, 19, 8, 0, 0), UTC()));
    f.users = new ManageUsersUseCase(f.userRepo, f.roleRepo, new PlainHasher, f.events, clock, new SequentialIds("u"));
    f.roles = new ManageRolesUseCase(f.roleRepo, f.userRepo, f.events, clock);
    f.roles.ensureBuiltIns();
    return f;
  }

  CreateUserRequest newUser(string name, string[] roles = null) {
    CreateUserRequest r;
    r.userName = name;
    r.password = "correct-horse";
    r.roles = roles;
    return r;
  }

  UpdateUserRequest withRoles(string[] roles) {
    UpdateUserRequest r;
    r.roles = nullable(roles);
    return r;
  }
}

///
unittest {
  auto f = fixture();
  auto uc = f.users;

  // first administrator with a generated password, only once
  auto boot = uc.ensureAdministrator("admin", "");
  assert(boot.created && boot.userName == "admin" && boot.generatedPassword.length == 20);
  assert(!uc.ensureAdministrator("admin", "whatever-123").created);
  auto admin = uc.authenticate("ADMIN", boot.generatedPassword);
  assert(admin.hasRole(adminRole) && admin.can("roles.manage") && admin.lastLoginAt.length > 0);

  // sign-in failures do not reveal whether the account exists
  assert(fails!AuthenticationException(() { uc.authenticate("admin", "wrong-password"); }));
  assert(fails!AuthenticationException(() { uc.authenticate("nobody", "wrong-password"); }));
  assert(fails!AuthenticationException(() { uc.authenticate("not valid!", "x"); }));

  // create, validation, uniqueness; viewer is the default role
  auto jane = uc.create(CreateUserRequest("Jane", "correct-horse", "Jane Doe", "jane@example.org"), "admin");
  assert(jane.userName == "jane" && jane.roles == [viewerRole] && jane.rights == ["status.read"] && jane.active);
  assert(fails!ConflictException(() { uc.create(newUser("jane"), "admin"); }));
  assert(fails!ValidationException(() { uc.create(CreateUserRequest("bob", "short"), "admin"); }));
  assert(fails!ValidationException(() { uc.create(newUser("bob", ["root"]), "admin"); }));

  // deactivated accounts cannot sign in
  UpdateUserRequest off;
  off.active = nullable(false);
  uc.update(jane.id, off, "admin");
  assert(fails!AuthenticationException(() { uc.authenticate("jane", "correct-horse"); }));
  UserDto session;
  assert(!uc.tryActive(jane.id, session) && uc.tryActive(admin.id, session));

  // the last active administrator stays
  assert(fails!InvalidStateTransitionException(() { uc.update(admin.id, withRoles([viewerRole]), "cli:root"); }));
  assert(fails!InvalidStateTransitionException(() { uc.remove(admin.id, "cli:root"); }));
  assert(fails!InvalidStateTransitionException(() { uc.remove(admin.id, "admin"); })); // own account
  assert(fails!ValidationException(() { uc.update(jane.id, withRoles([]), "admin"); }));

  auto promote = withRoles([adminRole, viewerRole]);
  promote.active = nullable(true);
  assert(uc.update(jane.id, promote, "admin").roles == [adminRole, viewerRole]);
  uc.update(admin.id, withRoles([viewerRole]), "jane"); // now allowed: jane is an active admin
  uc.remove(admin.id, "jane");
  assert(f.userRepo.items.length == 1);

  // passwords
  assert(fails!ValidationException(() { uc.changeOwnPassword(jane.id, "wrong-one!", "another-pass"); }));
  uc.changeOwnPassword(jane.id, "correct-horse", "battery-staple");
  uc.authenticate("jane", "battery-staple");
  uc.resetPassword(jane.id, "reset-by-admin", "jane");
  uc.authenticate("jane", "reset-by-admin");
  assert(f.events.published.length > 0 && f.events.published[$ - 1].type == "user.login");
}

/// Roles and the no-escalation rule.
unittest {
  auto f = fixture();
  f.users.ensureAdministrator("admin", "admin-password");
  assert(f.roles.list.length == 3 && f.roles.get(adminRole).locked && f.roles.get(adminRole).members == 1);
  assert(f.roles.rights.length == accessRights.length);

  // a user manager: may manage users, but only up to its own rights
  auto managers = f.roles.create(CreateRoleRequest("Managers", "User managers", "",
    ["status.read", "users.read", "users.manage"]), "admin");
  assert(managers.name == "managers" && managers.rights == ["status.read", "users.read", "users.manage"]);
  assert(fails!ConflictException(() { f.roles.create(CreateRoleRequest("managers"), "admin"); }));
  auto unknownRight = CreateRoleRequest("x1", "", "", ["users.everything"]);
  assert(fails!ValidationException(() { f.roles.create(unknownRight, "admin"); }));

  auto mia = f.users.create(newUser("mia", ["managers"]), "admin");
  assert(mia.can("users.manage") && !mia.can("roles.read"));
  auto viewer = f.users.create(newUser("vic"), "mia");
  assert(fails!PolicyViolationException(() { f.users.create(newUser("eve", [adminRole]), "mia"); }));
  assert(fails!PolicyViolationException(() { f.users.update(viewer.id, withRoles([auditorRole]), "mia"); }));
  auto admin = f.users.list[0];
  assert(admin.userName == "admin");
  assert(fails!PolicyViolationException(() { f.users.resetPassword(admin.id, "taken-over!", "mia"); }));
  assert(fails!PolicyViolationException(() { f.users.remove(admin.id, "mia"); }));
  f.users.resetPassword(viewer.id, "new-password", "mia");

  // role rights: changes apply to the members at once
  UpdateRoleRequest more;
  more.rights = nullable(["status.read", "users.read", "users.manage", "roles.read"]);
  assert(fails!PolicyViolationException(() { f.roles.update("managers", more, "mia"); }));
  f.roles.update("managers", more, "admin");
  UserDto now;
  assert(f.users.tryActive(mia.id, now) && now.can("roles.read"));

  UpdateRoleRequest everything;
  everything.rights = nullable(["status.read"]);
  assert(fails!InvalidStateTransitionException(() { f.roles.update(adminRole, everything, "admin"); }));

  // removal: not built-in, not in use
  assert(fails!InvalidStateTransitionException(() { f.roles.remove(viewerRole, "admin"); }));
  assert(fails!ConflictException(() { f.roles.remove("managers", "admin"); }));
  f.users.update(mia.id, withRoles([viewerRole]), "admin");
  f.roles.remove("managers", "admin");
  assert(fails!NotFoundException(() { f.roles.get("managers"); }));

  // ensureBuiltIns leaves changed built-in roles alone
  UpdateRoleRequest auditors;
  auditors.label = nullable("Revision");
  f.roles.update(auditorRole, auditors, "admin");
  f.roles.ensureBuiltIns();
  assert(f.roles.get(auditorRole).label == "Revision");
}
