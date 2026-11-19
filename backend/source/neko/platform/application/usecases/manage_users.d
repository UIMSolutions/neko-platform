/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web user accounts: sign-in, the first administrator, account management.
module neko.platform.application.usecases.manage_users;

import std.algorithm : count, map, sort;
import std.array : array;
import std.string : strip, toLower;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.ports;

@safe:

class ManageUsersUseCase : IManageUsersUseCase, IAuthenticateUseCase {
  private IUserRepository users;
  private IPasswordHasher hasher;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  /// Verified for unknown user names, so a failed sign-in takes the same time
  /// whether or not the account exists.
  private string dummyHash;

  this(IUserRepository users, IPasswordHasher hasher, IEventPublisher events, IClock clock, IIdGenerator ids) {
    this.users = users;
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
    return account.toDto;
  }

  bool tryActive(string id, out UserDto user) {
    UserAccount account;
    if (id.length == 0 || !users.tryGet(AccountId(id), account) || !account.active)
      return false;
    user = account.toDto;
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
    r.role = "admin";
    auto created = create(r, "system");
    result.created = true;
    result.userName = created.userName;
    return result;
  }

  // ── IManageUsersUseCase ─────────────────────────────────────────────────

  UserDto[] list() {
    auto all = users.all;
    all.sort!((a, b) => a.userName.value < b.userName.value);
    return all.map!(a => a.toDto).array;
  }

  UserDto get(string id) {
    return load(id).toDto;
  }

  UserDto create(CreateUserRequest request, string actor) {
    auto name = UserName(request.userName);
    UserAccount existing;
    if (users.tryGetByName(name.value, existing))
      throw new ConflictException("A user named '" ~ name.value ~ "' already exists");
    PasswordPolicy.require(request.password);

    auto now = clock.now;
    UserAccount account;
    account.id = AccountId(ids.newId);
    account.userName = name;
    account.createdAt = now;
    account.changeProfile(request.displayName, request.email, now);
    account.changeRole(parseRole(request.role.length > 0 ? request.role : "viewer"), now);
    account.setActive(request.active, now);
    account.changePasswordHash(hasher.hash(request.password), now);
    users.save(account);
    emit("user.created", account.id.value, actor, "Created " ~ account.role.roleLabel ~ " " ~ name.value);
    return account.toDto;
  }

  UserDto update(string id, UpdateUserRequest request, string actor) {
    auto account = load(id);
    auto now = clock.now;
    account.changeProfile(request.displayName.isNull ? account.displayName : request.displayName.get,
      request.email.isNull ? account.email : request.email.get, now);
    auto wasActiveAdmin = account.isActiveAdmin;
    if (!request.role.isNull)
      account.changeRole(parseRole(request.role.get), now);
    if (!request.active.isNull)
      account.setActive(request.active.get, now);
    if (wasActiveAdmin && !account.isActiveAdmin)
      requireAnotherActiveAdmin(account, "demote or deactivate");
    users.save(account);
    emit("user.changed", account.id.value, actor, "Changed user " ~ account.userName.value);
    return account.toDto;
  }

  void resetPassword(string id, string password, string actor) {
    auto account = load(id);
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
    if (account.isActiveAdmin)
      requireAnotherActiveAdmin(account, "remove");
    users.remove(account.id);
    emit("user.removed", account.id.value, actor, "Removed user " ~ account.userName.value);
  }

  // ── helpers ─────────────────────────────────────────────────────────────

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

private UserRole parseRole(string text) {
  UserRole role;
  if (!tryParseEnum!UserRole(text.strip.toLower, role))
    throw new ValidationException("Unknown role '" ~ text ~ "' (allowed: viewer, admin)");
  return role;
}

private string roleLabel(UserRole role) {
  return role == UserRole.admin ? "administrator" : "viewer";
}

version (unittest) {
  import std.typecons : nullable;
  import neko.platform.application.services : FixedClock, SequentialIds;
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
}

///
unittest {
  auto repo = new FakeUsers;
  auto events = new NoEvents;
  auto uc = new ManageUsersUseCase(repo, new PlainHasher, events, new FixedClock(SysTime(DateTime(2026, 11, 19, 8, 0, 0), UTC())), new SequentialIds("u"));

  // first administrator with a generated password, only once
  auto boot = uc.ensureAdministrator("admin", "");
  assert(boot.created && boot.userName == "admin" && boot.generatedPassword.length == 20);
  assert(!uc.ensureAdministrator("admin", "whatever-123").created);
  auto admin = uc.authenticate("ADMIN", boot.generatedPassword);
  assert(admin.isAdmin && admin.lastLoginAt.length > 0);

  // sign-in failures do not reveal whether the account exists
  assert(fails!AuthenticationException(() { uc.authenticate("admin", "wrong-password"); }));
  assert(fails!AuthenticationException(() { uc.authenticate("nobody", "wrong-password"); }));
  assert(fails!AuthenticationException(() { uc.authenticate("not valid!", "x"); }));

  // create, validation, uniqueness
  auto jane = uc.create(CreateUserRequest("Jane", "correct-horse", "Jane Doe", "jane@example.org"), "admin");
  assert(jane.userName == "jane" && jane.role == "viewer" && jane.active);
  assert(fails!ConflictException(() { uc.create(CreateUserRequest("jane", "correct-horse"), "admin"); }));
  assert(fails!ValidationException(() { uc.create(CreateUserRequest("bob", "short"), "admin"); }));
  assert(fails!ValidationException(() { uc.create(CreateUserRequest("bob", "long-enough", "", "", "root"), "admin"); }));

  // deactivated accounts cannot sign in
  UpdateUserRequest off;
  off.active = nullable(false);
  uc.update(jane.id, off, "admin");
  assert(fails!AuthenticationException(() { uc.authenticate("jane", "correct-horse"); }));
  UserDto session;
  assert(!uc.tryActive(jane.id, session) && uc.tryActive(admin.id, session));

  // the last active administrator stays
  UpdateUserRequest demote;
  demote.role = nullable("viewer");
  assert(fails!InvalidStateTransitionException(() { uc.update(admin.id, demote, "jane"); }));
  assert(fails!InvalidStateTransitionException(() { uc.remove(admin.id, "jane"); }));
  assert(fails!InvalidStateTransitionException(() { uc.remove(admin.id, "admin"); })); // own account

  UpdateUserRequest promote;
  promote.role = nullable("admin");
  promote.active = nullable(true);
  uc.update(jane.id, promote, "admin");
  uc.update(admin.id, demote, "jane"); // now allowed: jane is an active admin
  uc.remove(admin.id, "jane");
  assert(repo.items.length == 1);

  // passwords
  assert(fails!ValidationException(() { uc.changeOwnPassword(jane.id, "wrong-one!", "another-pass"); }));
  uc.changeOwnPassword(jane.id, "correct-horse", "battery-staple");
  uc.authenticate("jane", "battery-staple");
  uc.resetPassword(jane.id, "reset-by-admin", "jane");
  uc.authenticate("jane", "reset-by-admin");
  assert(events.published.length > 0 && events.published[$ - 1].type == "user.login");
}
