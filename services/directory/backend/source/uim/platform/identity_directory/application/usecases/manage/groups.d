/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.manage.groups;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Interactor: groups. Standard groups hold users, nested groups also hold
/// groups (without cycles), dynamic groups take their members from a rule.
class ManageGroupsUseCase
  : ResourceUseCase!(DirectoryGroup, GroupId, CreateGroupRequest, UpdateGroupRequest),
  IManageGroupsUseCase {

  protected MembershipService memberships;

  this(DirectoryRepositories repos, MembershipService memberships, IDirectoryEventPublisher publisher,
      AuditTrail audit, NowFn clock) {
    super(repos, repos.groups, publisher, audit, clock, "Group", "identity.group",
      AuditKinds(AuditEventType.groupCreated, AuditEventType.groupUpdated, AuditEventType.groupDeleted));
    this.memberships = memberships;
  }

  override protected DirectoryGroup build(CreateGroupRequest r) {
    auto group = DirectoryGroup(r.tenantId);
    assignMatching(group, r.spec);
    check(group, DirectoryGroup.init);
    return group;
  }

  override protected void apply(ref DirectoryGroup group, GroupSpec spec) {
    auto before = group;
    assignMatching(group, spec);
    check(group, before);
  }

  protected void check(ref DirectoryGroup group, const DirectoryGroup before) {
    group.displayName = group.displayName.strip;
    validateDisplayName("Group name", group.displayName, 120);
    ensureUnique(repo.findByName(group.tenantId, group.displayName), group);
    group.externalId = group.externalId.strip;
    if (group.externalId.length > 0) {
      auto ext = group.externalId;
      auto id = group.id;
      ensureState(repo.findMatching(group.tenantId, (const DirectoryGroup o) => o.id != id && o.externalId == ext).length == 0,
        "External ID '" ~ ext ~ "' is already used by another group");
    }
    group.extendedAttributes = checkExtensions(group.extendedAttributes, repos.schemas.findByTenant(group.tenantId),
      SchemaTarget.group, before.extendedAttributes);

    group.membershipRule = group.membershipRule.strip;
    if (group.groupType == GroupType.dynamic) {
      validate(group.membershipRule.length > 0, "Dynamic group '" ~ group.displayName ~ "' needs a membership rule");
      group.members = memberships.evaluateRule(group.tenantId, group.membershipRule); // also checks the syntax
      group.evaluatedAt = clock();
      return;
    }
    validate(group.membershipRule.length == 0, "Only dynamic groups have a membership rule");
    GroupMember[] resolved;
    foreach (m; group.members) {
      auto member = resolveMember(group, m.value, m.type == MemberType.group && m.value.length ? "group" : "");
      if (!resolved.any!(r => r.value == member.value))
        resolved ~= member;
    }
    group.members = resolved;
  }

  /// A member reference (id, user name or group name) as GroupMember; checks type rules and cycles.
  protected GroupMember resolveMember(const DirectoryGroup group, string reference, string memberType) {
    auto r = reference.strip;
    validate(r.length > 0, "Member reference is required");
    auto wanted = memberType.strip.toLower;
    validate(wanted.length == 0 || wanted == "user" || wanted == "group", "memberType must be user or group");

    if (wanted != "group") {
      auto user = repos.users.findById(group.tenantId, DirectoryUserId(r));
      if (user.isNull)
        user = repos.users.findByName(group.tenantId, r);
      if (!user.isNull)
        return GroupMember(user.id.value, MemberType.user, user.userName);
    }
    if (wanted != "user") {
      auto sub = repos.groups.findById(group.tenantId, GroupId(r));
      if (sub.isNull)
        sub = repos.groups.findByName(group.tenantId, r);
      if (!sub.isNull) {
        ensureState(group.groupType == GroupType.nested, "Group '" ~ group.displayName
            ~ "' is a " ~ enumText(group.groupType) ~ " group — only nested groups can contain groups");
        const(string)[] children(string id) {
          auto g = id == group.id.value ? group : repos.groups.findById(group.tenantId, GroupId(id));
          return g.memberIds(MemberType.group);
        }

        ensureState(!createsCycle(group.id.value, sub.id.value, &children), "Adding group '" ~ sub.displayName
            ~ "' to '" ~ group.displayName ~ "' would create a cycle");
        return GroupMember(sub.id.value, MemberType.group, sub.displayName);
      }
    }
    throw new DirectoryNotFoundException((wanted.length ? wanted.capitalize : "User or group") ~ " '" ~ r ~ "' not found");
  }

  override protected void afterChange(DirectoryGroup group, DirectoryGroup before) {
    if (!before.isNull && before.displayName != group.displayName)
      memberships.renameEverywhere(group.tenantId, group.id.value, group.displayName);
    memberships.syncUsers(group.tenantId);
  }

  override protected void afterRemove(DirectoryGroup group) {
    memberships.removeEverywhere(group.tenantId, group.id.value);
    memberships.syncUsers(group.tenantId);
  }

  UsecaseResult addMember(TenantId tenantId, GroupId id, string member, string memberType, UserId actor) {
    return transition(tenantId, id, actor, "member '" ~ member ~ "' added", AuditEventType.memberAdded, (ref DirectoryGroup g) {
      ensureState(g.groupType != GroupType.dynamic, "Members of dynamic group '" ~ g.displayName ~ "' come from its rule");
      auto m = resolveMember(g, member, memberType);
      ensureState(!g.hasMember(m.value), "'" ~ m.display ~ "' is already a member of '" ~ g.displayName ~ "'");
      g.members ~= m;
    });
  }

  UsecaseResult removeMember(TenantId tenantId, GroupId id, string member, UserId actor) {
    return transition(tenantId, id, actor, "member '" ~ member ~ "' removed", AuditEventType.memberRemoved, (ref DirectoryGroup g) {
      ensureState(g.groupType != GroupType.dynamic, "Members of dynamic group '" ~ g.displayName ~ "' come from its rule");
      auto r = member.strip;
      auto kept = g.members.filter!(m => m.value != r && !sameName(m.display, r)).array;
      ensureFound(kept.length < g.members.length, "'" ~ r ~ "' is not a member of '" ~ g.displayName ~ "'");
      g.members = kept;
    });
  }

  UsecaseResult evaluate(TenantId tenantId, GroupId id, UserId actor) {
    return transition(tenantId, id, actor, "evaluated", AuditEventType.groupUpdated, (ref DirectoryGroup g) {
      ensureState(g.groupType == GroupType.dynamic, "Group '" ~ g.displayName ~ "' is not dynamic");
      g.members = memberships.evaluateRule(tenantId, g.membershipRule);
      g.evaluatedAt = clock();
    });
  }
}
