/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A role: a named bundle of access rights, assigned to user accounts.
module neko.platform.domain.entities.role;

import std.algorithm : canFind, sort, uniq;
import std.array : array;
import std.datetime.systime : SysTime;
import std.string : strip;
import neko.platform.domain.enumerations;
import neko.platform.domain.exceptions;
import neko.platform.domain.types;

@safe:

struct Role {
  RoleName name;
  string label;
  string description;
  /// Sorted, without duplicates.
  AccessRight[] rights;
  /// Shipped with the platform: cannot be removed.
  bool builtIn;
  /// The catalogue the rights were decided on. Rights added by a later
  /// version are not in it; for built-in roles they are granted on start-up
  /// if the shipped role has them (see `upgradeBuiltIn`).
  AccessRight[] knownRights;
  SysTime createdAt;
  SysTime modifiedAt;

  /// The administrator role always grants every right, also rights added by
  /// later versions; its rights cannot be edited.
  bool isAdministrator() const pure nothrow {
    return name.value == adminRole;
  }

  bool grants(AccessRight right) const pure nothrow {
    return isAdministrator || rights.canFind(right);
  }

  AccessRight[] effectiveRights() const pure nothrow {
    return isAdministrator ? allAccessRights : rights.dup;
  }

  void describe(string label, string description, SysTime now) {
    auto l = label.strip, d = description.strip;
    if (l.length > 64)
      throw new ValidationException("Role label exceeds 64 characters");
    if (d.length > 256)
      throw new ValidationException("Role description exceeds 256 characters");
    this.label = l.length > 0 ? l : name.value;
    this.description = d;
    modifiedAt = now;
  }

  void grant(const(AccessRight)[] rights, SysTime now) {
    if (isAdministrator)
      throw new InvalidStateTransitionException("The rights of the administrator role cannot be changed");
    this.rights = rights.dup.sort.uniq.array;
    knownRights = allAccessRights;
    modifiedAt = now;
  }

  /// Grant the rights of `shipped` (the built-in role of this version) that
  /// are new since this role was last decided on. Returns true if it changed;
  /// rights taken away by an administrator stay away.
  bool upgradeBuiltIn(const Role shipped) {
    auto all = allAccessRights;
    if (covers(knownRights, all))
      return false;
    foreach (right; shipped.rights)
      if (!knownRights.canFind(right) && !rights.canFind(right))
        rights ~= right;
    rights = rights.sort.uniq.array;
    knownRights = all;
    return true;
  }
}

/// Union of the rights of the named roles, in catalogue order. Names
/// without a role (removed meanwhile) grant nothing.
AccessRight[] effectiveRights(const(string)[] roleNames, const(Role)[] roles) pure nothrow {
  AccessRight[] result;
  foreach (right; allAccessRights)
    foreach (r; roles)
      if (roleNames.canFind(r.name.value) && r.grants(right)) {
        result ~= right;
        break;
      }
  return result;
}

/// True if `held` contains every right of `wanted`.
bool covers(const(AccessRight)[] held, const(AccessRight)[] wanted) pure nothrow {
  foreach (w; wanted)
    if (!held.canFind(w))
      return false;
  return true;
}

/// The roles every platform instance starts with.
Role[] builtInRoles(SysTime now) {
  Role make(string name, string label, string description, AccessRight[] rights) {
    Role r;
    r.name = RoleName(name);
    r.builtIn = true;
    r.createdAt = now;
    r.describe(label, description, now);
    r.rights = rights.sort.uniq.array;
    r.knownRights = allAccessRights;
    return r;
  }

  return [
    make(adminRole, "Administrator", "Every access right, including users and roles", allAccessRights),
    make(auditorRole, "Auditor", "Reads everything, including events, monitoring, users and roles; changes nothing",
      [AccessRight.statusRead, AccessRight.eventsRead, AccessRight.monitoringRead, AccessRight.sitesRead,
        AccessRight.filesRead, AccessRight.securityRead, AccessRight.landscapeRead, AccessRight.billingRead,
        AccessRight.usersRead, AccessRight.rolesRead]),
    make(editorRole, "Editor", "Site content and files",
      [AccessRight.statusRead, AccessRight.sitesRead, AccessRight.sitesManage, AccessRight.filesRead,
        AccessRight.filesManage]),
    make(viewerRole, "Viewer", "Status page", [AccessRight.statusRead]),
  ];
}

///
unittest {
  auto roles = builtInRoles(SysTime.init);
  auto admin = roles[0], auditor = roles[1];
  assert(admin.isAdministrator && admin.grants(AccessRight.rolesManage));
  assert(auditor.grants(AccessRight.eventsRead) && !auditor.grants(AccessRight.usersManage));

  auditor.grant([AccessRight.usersRead, AccessRight.statusRead, AccessRight.usersRead], SysTime.init);
  assert(auditor.rights == [AccessRight.statusRead, AccessRight.usersRead]);

  assert(effectiveRights([auditorRole, "gone"], [admin, auditor]) == [AccessRight.statusRead, AccessRight.usersRead]);
  assert(effectiveRights([adminRole], roles) == allAccessRights);
  assert(covers(allAccessRights, auditor.rights) && !covers(auditor.rights, admin.effectiveRights));

  bool locked;
  try
    admin.grant([], SysTime.init);
  catch (InvalidStateTransitionException)
    locked = true;
  assert(locked);
}

/// Built-in roles stored by an older version gain the new rights once.
unittest {
  auto shipped = builtInRoles(SysTime.init)[1]; // auditor
  Role old;
  old.name = RoleName(auditorRole);
  old.builtIn = true;
  old.rights = [AccessRight.statusRead, AccessRight.usersRead]; // events.read taken away by an admin
  old.knownRights = firstAccessRights.dup;
  assert(old.upgradeBuiltIn(shipped));
  assert(old.grants(AccessRight.monitoringRead) && old.grants(AccessRight.filesRead));
  assert(!old.grants(AccessRight.eventsRead) && !old.grants(AccessRight.rolesRead));
  old.grant([AccessRight.statusRead], SysTime.init);
  assert(!old.upgradeBuiltIn(shipped) && old.rights == [AccessRight.statusRead]);
}
