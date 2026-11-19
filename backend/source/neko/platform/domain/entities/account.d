/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A user account for the web pages of one platform instance (security domain).
module neko.platform.domain.entities.account;

import std.algorithm : canFind;
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
  UserRole role = UserRole.viewer;
  bool active = true;
  /// Produced by the password hasher port; never the password itself.
  string passwordHash;
  SysTime createdAt;
  SysTime modifiedAt;
  SysTime lastLoginAt;
  SysTime passwordChangedAt;

  bool isAdmin() const pure nothrow {
    return role == UserRole.admin;
  }

  /// Active administrators are the ones who can manage accounts.
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

  void changeRole(UserRole role, SysTime now) pure nothrow {
    this.role = role;
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
  a.changeRole(UserRole.admin, now);
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
