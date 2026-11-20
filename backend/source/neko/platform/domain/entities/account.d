/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A user account for the web pages of one platform instance (security domain).
module neko.platform.domain.entities.account;

import std.algorithm : canFind, sort, uniq;
import std.array : array;
import std.datetime.systime : SysTime;
import std.string : strip;
import neko.platform.domain.enumerations;
import neko.platform.domain.exceptions;
import neko.platform.domain.types;

@safe:

struct UserAccount {
  AccountId id;
  UserName userName;
  string displayName;
  string email;
  /// Names of the assigned roles, sorted, without duplicates. What the
  /// account may do is the union of their rights.
  string[] roles;
  bool active = true;
  /// Produced by the password hasher port; never the password itself.
  string passwordHash;
  SysTime createdAt;
  SysTime modifiedAt;
  SysTime lastLoginAt;
  SysTime passwordChangedAt;

  bool hasRole(string name) const pure nothrow {
    return roles.canFind(name);
  }

  /// Holds the built-in administrator role.
  bool isAdmin() const pure nothrow {
    return hasRole(adminRole);
  }

  /// At least one active administrator must remain, so every right stays reachable.
  bool isActiveAdmin() const pure nothrow {
    return active && isAdmin;
  }

  /// The name shown in the UI.
  string label() const pure nothrow {
    return displayName.length > 0 ? displayName : userName.value;
  }

  void changeProfile(string displayName, string email, SysTime now) {
    auto mail = email.strip;
    if (mail.length > 0 && (!mail.canFind('@') || mail.length > 254))
      throw new ValidationException("'" ~ mail ~ "' is not an e-mail address");
    if (displayName.strip.length > 128)
      throw new ValidationException("Display name exceeds 128 characters");
    this.displayName = displayName.strip;
    this.email = mail;
    modifiedAt = now;
  }

  /// `names` are validated role names; whether the roles exist is checked by the caller.
  void assignRoles(const(RoleName)[] names, SysTime now) {
    if (names.length == 0)
      throw new ValidationException("A user needs at least one role");
    string[] list;
    foreach (n; names)
      list ~= n.value;
    roles = list.sort.uniq.array;
    modifiedAt = now;
  }

  void setActive(bool active, SysTime now) pure nothrow {
    this.active = active;
    modifiedAt = now;
  }

  void changePasswordHash(string hash, SysTime now) pure nothrow {
    passwordHash = hash;
    passwordChangedAt = now;
    modifiedAt = now;
  }

  void recordLogin(SysTime now) pure nothrow {
    lastLoginAt = now;
  }
}

///
unittest {
  import std.datetime.systime : Clock;

  auto now = Clock.currTime;
  UserAccount a;
  a.userName = UserName("jane");
  assert(a.label == "jane" && !a.isAdmin);
  a.changeProfile(" Jane Doe ", "jane@example.org", now);
  assert(a.label == "Jane Doe");
  assert(a.roles.length == 0 && !a.isAdmin);
  a.assignRoles([RoleName("viewer"), RoleName("Admin"), RoleName("admin")], now);
  assert(a.roles == [adminRole, viewerRole]);
  assert(a.isActiveAdmin);
  a.setActive(false, now);
  assert(!a.isActiveAdmin);

  bool rejected;
  try
    a.changeProfile("", "not-a-mail", now);
  catch (ValidationException)
    rejected = true;
  assert(rejected);
}
