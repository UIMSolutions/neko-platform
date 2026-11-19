/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.entities.group;

import neko.directory;

mixin(ShowModule!());

@safe:

/// A group of users (SCIM 2.0 group). Nested groups may contain other groups,
/// dynamic groups compute their members from a membership rule.
struct DirectoryGroup {
  mixin TenantEntity!GroupId;

  string displayName; /// unique per tenant (case-insensitive)
  string externalId;
  string description;
  GroupType groupType = GroupType.standard;
  /// SCIM filter selecting the members of a dynamic group, e.g. `userType eq "employee" and title co "Sales"`.
  string membershipRule;
  GroupMember[] members;
  ExtendedAttribute[] extendedAttributes;
  /// Last evaluation of the membership rule (dynamic groups).
  long evaluatedAt;
}

/// True if the group has a direct member with this id.
bool hasMember(const DirectoryGroup group, string memberId) {
  return group.members.any!(m => m.value == memberId);
}

/// Ids of the direct members of a type.
string[] memberIds(const DirectoryGroup group, MemberType type) {
  string[] ids;
  foreach (m; group.members)
    if (m.type == type)
      ids ~= m.value;
  return ids;
}

///
unittest {
  auto g = DirectoryGroup(TenantId("t1"));
  g.members = [GroupMember("u1", MemberType.user, "jane"), GroupMember("g2", MemberType.group, "Sales")];
  assert(g.hasMember("u1") && !g.hasMember("u2"));
  assert(g.memberIds(MemberType.group) == ["g2"]);
}
