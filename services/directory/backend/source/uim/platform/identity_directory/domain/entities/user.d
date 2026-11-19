/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.entities.user;

import neko.directory;

mixin(ShowModule!());

@safe:

/// A user of the directory (SCIM 2.0 core user + custom schema extensions).
/// Plain data: no serialization code (see helpers.codec), behaviour lives in
/// the domain services (passwords, lockout, schemas).
struct DirectoryUser {
  mixin TenantEntity!DirectoryUserId;

  string userName; /// unique per tenant (case-insensitive)
  string externalId; /// id in the provisioning source, unique if set
  string displayName;
  string givenName;
  string familyName;
  string middleName;
  string honorificPrefix;
  string honorificSuffix;
  string nickName;
  string title;
  string profileUrl;
  UserType userType = UserType.employee;
  string preferredLanguage = "en";
  string locale;
  string timezone;
  UserStatus status = UserStatus.active;

  Email[] emails;
  PhoneNumber[] phoneNumbers;
  PostalAddress[] addresses;
  ExtendedAttribute[] extendedAttributes;

  /// Display names of the groups the user is a direct member of (maintained by the group interactor).
  string[] groups;
  /// Display names of the groups the user belongs to through nested groups.
  string[] inheritedGroups;

  /// Name of the password policy ("" = default policy of the tenant).
  string passwordPolicy;

  // ── credentials and sign-in state (maintained by the interactors) ─────────
  string passwordHash; /// never exposed
  string[] passwordHistory; /// previous hashes, newest first — never exposed
  bool passwordSet;
  bool mustChangePassword;
  long passwordChangedAt;
  int failedLoginAttempts;
  long lockedAt;
  long unlockAt; /// automatic unlock (0 = only by an administrator)
  long lastLoginAt;
}

/// "Jane Doe" — the display name, the formatted name or the user name.
string fullName(const DirectoryUser user) {
  if (user.displayName.length > 0)
    return user.displayName;
  auto name = [user.givenName, user.middleName, user.familyName].filter!(s => s.length > 0).join(" ");
  return name.length > 0 ? name : user.userName;
}

/// The primary e-mail address (the first one if none is marked primary).
string primaryEmail(const DirectoryUser user) {
  foreach (e; user.emails)
    if (e.primary)
      return e.value;
  return user.emails.length > 0 ? user.emails[0].value : "";
}

///
unittest {
  auto u = DirectoryUser(TenantId("t1"));
  u.userName = "jane";
  assert(fullName(u) == "jane");
  u.givenName = "Jane";
  u.familyName = "Doe";
  assert(fullName(u) == "Jane Doe");
  u.emails = [Email("a@x.io"), Email("b@x.io", "home", true)];
  assert(primaryEmail(u) == "b@x.io");
}
