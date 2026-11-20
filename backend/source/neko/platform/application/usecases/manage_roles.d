/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Roles: named bundles of access rights, assigned to user accounts.
module neko.platform.application.usecases.manage_roles;

import std.algorithm : count, map, sort;
import std.array : array, join;
import std.string : strip;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.application.usecases.access;
import neko.platform.ports;

@safe:

class ManageRolesUseCase : IManageRolesUseCase {
  private IRoleRepository roles;
  private IUserRepository users;
  private IEventPublisher events;
  private IClock clock;

  this(IRoleRepository roles, IUserRepository users, IEventPublisher events, IClock clock) {
    this.roles = roles;
    this.users = users;
    this.events = events;
    this.clock = clock;
  }

  RoleDto[] list() {
    auto all = roles.all;
    all.sort!((a, b) => a.name.value < b.name.value);
    auto accounts = users.all;
    return all.map!(r => r.toDto(members(accounts, r.name.value))).array;
  }

  RoleDto get(string name) {
    auto role = load(name);
    return role.toDto(members(users.all, role.name.value));
  }

  AccessRightDto[] rights() {
    return accessRights.map!(i => i.toDto).array;
  }

  RoleDto create(CreateRoleRequest request, string actor) {
    auto name = RoleName(request.name);
    Role existing;
    if (roles.tryGet(name.value, existing))
      throw new ConflictException("A role named '" ~ name.value ~ "' already exists");
    auto granted = parseRights(request.rights);
    requireCovers(users, roles, actor, granted, "create this role");

    auto now = clock.now;
    Role role;
    role.name = name;
    role.createdAt = now;
    role.describe(request.label, request.description, now);
    role.grant(granted, now);
    roles.save(role);
    emit("role.created", role.name.value, actor, "Created role " ~ role.name.value ~ " (" ~ rightList(role) ~ ")");
    return role.toDto(0);
  }

  RoleDto update(string name, UpdateRoleRequest request, string actor) {
    auto role = load(name);
    // Changing a role means controlling everyone who holds it.
    requireCovers(users, roles, actor, role.effectiveRights, "change the role '" ~ role.name.value ~ "'");
    auto now = clock.now;
    role.describe(request.label.isNull ? role.label : request.label.get,
      request.description.isNull ? role.description : request.description.get, now);
    if (!request.rights.isNull) {
      auto granted = parseRights(request.rights.get);
      requireCovers(users, roles, actor, granted, "grant these rights");
      role.grant(granted, now);
    }
    roles.save(role);
    emit("role.changed", role.name.value, actor, "Changed role " ~ role.name.value ~ " (" ~ rightList(role) ~ ")");
    return role.toDto(members(users.all, role.name.value));
  }

  void remove(string name, string actor) {
    auto role = load(name);
    if (role.builtIn)
      throw new InvalidStateTransitionException("The built-in role '" ~ role.name.value ~ "' cannot be removed");
    requireCovers(users, roles, actor, role.effectiveRights, "remove the role '" ~ role.name.value ~ "'");
    auto holders = members(users.all, role.name.value);
    if (holders > 0)
      throw new ConflictException("The role '" ~ role.name.value ~ "' is still assigned to " ~ countText(holders)
          ~ "; take it away from them first");
    roles.remove(role.name.value);
    emit("role.removed", role.name.value, actor, "Removed role " ~ role.name.value);
  }

  void ensureBuiltIns() {
    foreach (role; builtInRoles(clock.now)) {
      Role existing;
      if (!roles.tryGet(role.name.value, existing))
        roles.save(role);
      else if (existing.builtIn && existing.upgradeBuiltIn(role)) {
        roles.save(existing);
        emit("role.upgraded", existing.name.value, "system", "Granted the new rights of this version to "
            ~ existing.name.value ~ " (" ~ rightList(existing) ~ ")");
      }
    }
  }

  private Role load(string name) {
    Role role;
    if (!roles.tryGet(name.strip, role))
      throw new NotFoundException("Role", name);
    return role;
  }

  private void emit(string type, string subject, string actor, string message) {
    events.publish(PlatformEvent(type, subject, actor, message, clock.now));
  }
}

/// Access right keys → rights; throws on unknown keys.
AccessRight[] parseRights(const(string)[] keys) {
  AccessRight[] result;
  foreach (k; keys) {
    AccessRight right;
    if (!tryParseAccessRight(k.strip, right))
      throw new ValidationException("Unknown access right '" ~ k ~ "' (allowed: "
          ~ accessRights.map!(i => i.key).join(", ") ~ ")");
    result ~= right;
  }
  return result;
}

private long members(const(UserAccount)[] accounts, string role) {
  return accounts.count!(a => a.hasRole(role));
}

private string rightList(const Role role) {
  auto keys = role.effectiveRights.map!(r => r.key).array;
  return keys.length ? keys.join(", ") : "no rights";
}

private string countText(long n) {
  import std.conv : to;

  return n.to!string ~ (n == 1 ? " account" : " accounts");
}
