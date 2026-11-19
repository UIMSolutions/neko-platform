/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.services.memberships;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Application service keeping group memberships consistent:
///   * users carry the display names of their direct and inherited groups
///   * member display texts follow renames
///   * deleted users and groups disappear from all groups
///   * dynamic groups follow their membership rules
class MembershipService {
  protected DirectoryRepositories repos;
  protected NowFn clock;

  this(DirectoryRepositories repos, NowFn clock) {
    this.repos = repos;
    this.clock = clock;
  }

  /// Recompute `groups` / `inheritedGroups` of all users of the tenant.
  /// Returns the number of users changed.
  int syncUsers(TenantId tenantId) {
    auto groups = repos.groups.findByTenant(tenantId);
    string[][string] parentsOf; // group id → ids of groups containing it
    string[string] nameOf_;
    foreach (g; groups) {
      nameOf_[g.id.value] = g.displayName;
      foreach (m; g.members)
        if (m.type == MemberType.group)
          parentsOf[m.value] ~= g.id.value;
    }
    const(string)[] parents(string id) {
      return parentsOf.get(id, null);
    }

    int changed;
    foreach (user; repos.users.findByTenant(tenantId)) {
      auto direct = groups.filter!(g => g.members.any!(m => m.type == MemberType.user && m.value == user.id.value))
        .map!(g => g.id.value).array;
      auto inherited = ancestorGroups(direct, &parents);
      auto directNames = direct.map!(id => nameOf_[id]).array.sort.array;
      auto inheritedNames = inherited.map!(id => nameOf_[id]).array.sort.array;
      if (user.groups == directNames && user.inheritedGroups == inheritedNames)
        continue;
      user.groups = directNames;
      user.inheritedGroups = inheritedNames;
      repos.users.update(user);
      changed++;
    }
    return changed;
  }

  /// Remove a user or group (by id) from all groups.
  void removeEverywhere(TenantId tenantId, string memberId) {
    foreach (g; repos.groups.findMatching(tenantId, (const DirectoryGroup x) => x.hasMember(memberId))) {
      g.members = g.members.filter!(m => m.value != memberId).array;
      g.updatedAt = clock();
      repos.groups.update(g);
    }
  }

  /// Update the display text of a member (after a rename).
  void renameEverywhere(TenantId tenantId, string memberId, string display) {
    foreach (g; repos.groups.findMatching(tenantId, (const DirectoryGroup x) => x.members.any!(m => m.value == memberId && m.display != display))) {
      foreach (ref m; g.members)
        if (m.value == memberId)
          m.display = display;
      repos.groups.update(g);
    }
  }

  /// Members of a dynamic group according to its rule.
  GroupMember[] evaluateRule(TenantId tenantId, string rule) {
    auto filter = parseScimFilter(rule);
    auto schemas = repos.schemas.findByTenant(tenantId);
    GroupMember[] members;
    foreach (u; repos.users.findByTenant(tenantId))
      if (filter.matches(ruleView(u, schemas)))
        members ~= GroupMember(u.id.value, MemberType.user, u.userName);
    members.sort!((a, b) => a.display < b.display);
    return members;
  }

  /// Re-evaluate all dynamic groups. Returns the names of the groups whose members changed.
  string[] refreshDynamicGroups(TenantId tenantId) {
    string[] changed;
    foreach (g; repos.groups.findMatching(tenantId, (const DirectoryGroup x) => x.groupType == GroupType.dynamic)) {
      GroupMember[] members;
      try
        members = evaluateRule(tenantId, g.membershipRule);
      catch (DirectoryException e) {
        logWarn("identity-directory: rule of group '%s' is invalid: %s", g.displayName, e.msg);
        continue;
      }
      g.evaluatedAt = clock();
      if (members.map!(m => m.value).array != g.members.map!(m => m.value).array)
        changed ~= g.displayName;
      g.members = members;
      repos.groups.update(g);
    }
    return changed;
  }
}
