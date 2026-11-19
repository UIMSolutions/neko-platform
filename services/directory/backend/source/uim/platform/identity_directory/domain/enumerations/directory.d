/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Business enumerations of users, groups and custom schemas.
module neko.directory.domain.enumerations.directory;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Lifecycle of a user account.
enum UserStatus {
  active, /// can sign in
  inactive, /// deactivated by an administrator (SCIM active = false)
  locked, /// too many failed sign-ins or locked by an administrator
  staged, /// provisioned, not yet activated
  pending, /// awaiting confirmation (e.g. e-mail verification)
}

/// Kind of user (SCIM userType).
enum UserType {
  employee,
  contractor,
  partner,
  customer,
  public_,
}

/// Kind of group member.
enum MemberType {
  user,
  group,
}

/// Kind of group.
enum GroupType {
  standard, /// users only
  nested, /// users and other groups (no cycles)
  dynamic, /// members computed from a membership rule (SCIM filter)
}

/// Resource a custom schema extends.
enum SchemaTarget {
  user,
  group,
}

/// SCIM attribute data types (RFC 7643 section 2.3).
enum AttributeType {
  string_,
  boolean,
  decimal,
  integer,
  dateTime,
  reference,
  binary,
}

/// SCIM attribute mutability.
enum Mutability {
  readWrite,
  readOnly,
  writeOnly,
  immutable_,
}

/// SCIM attribute "returned" behaviour.
enum Returned {
  always,
  never,
  default_,
  request,
}

/// SCIM attribute uniqueness.
enum Uniqueness {
  none,
  server,
  global,
}

/// Status of user status values that allow signing in.
bool canSignIn(UserStatus status) pure nothrow {
  return status == UserStatus.active;
}

///
unittest {
  assert(enumText(AttributeType.string_) == "string");
  assert(enumText(UserType.public_) == "public");
  assert(parseEnum!Mutability("immutable", Mutability.readWrite) == Mutability.immutable_);
  assert(parseEnum!Returned("default", Returned.always) == Returned.default_);
  assert(parseEnum!UserStatus("LOCKED", UserStatus.active) == UserStatus.locked);
  assert(UserStatus.active.canSignIn && !UserStatus.locked.canSignIn);
}
