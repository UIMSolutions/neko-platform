/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Access rights of web users. The catalogue is fixed (code decides what a
/// right allows); roles bundle rights and are managed at runtime.
///
/// The member names double as vibe.web.auth role names: `@auth(Role.usersManage)`
/// calls `PageContext.isUsersManage()`.
module neko.platform.domain.enumerations.rights;

import std.traits : EnumMembers;

@safe:

enum AccessRight {
  /// Status page: key figures, capabilities, service catalogue.
  statusRead,
  /// Recent platform events (audit trail) on the status page.
  eventsRead,
  /// List user accounts.
  usersRead,
  /// Create, change, reset and remove user accounts.
  usersManage,
  /// List roles and their rights.
  rolesRead,
  /// Create, change and remove roles.
  rolesManage,
}

/// Describes one access right for the UI and the CLI.
struct AccessRightInfo {
  AccessRight right;
  /// Stable textual key, stored in role documents ("users.manage").
  string key;
  string label;
  string description;
  /// Heading the right is grouped under.
  string area;
}

/// Every access right, in display order.
immutable AccessRightInfo[] accessRights = [
  AccessRightInfo(AccessRight.statusRead, "status.read", "View status",
    "Key figures, capabilities and the service catalogue", "Status"),
  AccessRightInfo(AccessRight.eventsRead, "events.read", "View events",
    "Recent platform events (audit trail), incl. sign-ins", "Status"),
  AccessRightInfo(AccessRight.usersRead, "users.read", "View users",
    "List user accounts and their roles", "Users"),
  AccessRightInfo(AccessRight.usersManage, "users.manage", "Manage users",
    "Create, change, deactivate and remove accounts; reset passwords", "Users"),
  AccessRightInfo(AccessRight.rolesRead, "roles.read", "View roles",
    "List roles and the rights they grant", "Roles"),
  AccessRightInfo(AccessRight.rolesManage, "roles.manage", "Manage roles",
    "Create, change and remove roles", "Roles"),
];

static assert(accessRights.length == [EnumMembers!AccessRight].length, "Describe every AccessRight");

AccessRightInfo info(AccessRight right) pure nothrow @nogc {
  return accessRights[right];
}

string key(AccessRight right) pure nothrow @nogc {
  return accessRights[right].key;
}

/// "users.manage" → AccessRight.usersManage
bool tryParseAccessRight(string key, out AccessRight right) pure nothrow @nogc {
  foreach (i; accessRights)
    if (i.key == key) {
      right = i.right;
      return true;
    }
  return false;
}

/// Every right, for the administrator role.
AccessRight[] allAccessRights() pure nothrow {
  return [EnumMembers!AccessRight].dup;
}

/// Names of the built-in roles.
enum adminRole = "admin";
enum auditorRole = "auditor";
enum viewerRole = "viewer";

///
unittest {
  foreach (i, entry; accessRights)
    assert(entry.right == i, "accessRights must follow the enum order");
  AccessRight r;
  assert(tryParseAccessRight("users.manage", r) && r == AccessRight.usersManage);
  assert(!tryParseAccessRight("usersManage", r));
  assert(AccessRight.rolesRead.key == "roles.read");
}
