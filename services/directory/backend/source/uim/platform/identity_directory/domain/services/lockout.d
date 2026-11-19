/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Sign-in state machine: failed attempts, lockout and automatic unlock.
module neko.directory.domain.services.lockout;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Lock a user (by an administrator: no automatic unlock when minutes = 0).
void lockUser(ref DirectoryUser user, long now, int minutes) {
  user.status = UserStatus.locked;
  user.lockedAt = now;
  user.unlockAt = minutes > 0 ? now + minutes * 600_000_000L : 0;
}

/// Unlock a user and reset the failed attempt counter.
void unlockUser(ref DirectoryUser user) {
  user.status = UserStatus.active;
  user.failedLoginAttempts = 0;
  user.lockedAt = 0;
  user.unlockAt = 0;
}

/// Register a failed sign-in. Returns true if the user got locked by it.
bool registerFailedLogin(ref DirectoryUser user, const PasswordPolicy policy, long now) {
  user.failedLoginAttempts++;
  if (policy.maxFailedAttempts > 0 && user.failedLoginAttempts >= policy.maxFailedAttempts
      && user.status == UserStatus.active) {
    lockUser(user, now, policy.lockoutMinutes);
    return true;
  }
  return false;
}

/// Register a successful sign-in.
void registerSuccessfulLogin(ref DirectoryUser user, long now) {
  user.failedLoginAttempts = 0;
  user.lastLoginAt = now;
}

/// True if a locked user is due for automatic unlock.
bool isUnlockDue(const DirectoryUser user, long now) pure nothrow {
  return user.status == UserStatus.locked && user.unlockAt > 0 && user.unlockAt <= now;
}

///
unittest {
  PasswordPolicy p;
  p.maxFailedAttempts = 3;
  p.lockoutMinutes = 10;
  auto u = DirectoryUser(TenantId("t1"));
  assert(!registerFailedLogin(u, p, 100));
  assert(!registerFailedLogin(u, p, 100));
  assert(registerFailedLogin(u, p, 100));
  assert(u.status == UserStatus.locked && u.unlockAt == 100 + 10 * 600_000_000L);
  assert(!isUnlockDue(u, 101) && isUnlockDue(u, u.unlockAt));
  unlockUser(u);
  assert(u.status == UserStatus.active && u.failedLoginAttempts == 0);
  registerSuccessfulLogin(u, 7);
  assert(u.lastLoginAt == 7);
}
