/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.services.statistics;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Application service: aggregated figures of a tenant.
class DirectoryStatisticsService : IDirectoryStatisticsService {
  protected DirectoryRepositories repos;
  protected NowFn clock;

  this(DirectoryRepositories repos, NowFn clock) {
    this.repos = repos;
    this.clock = clock;
  }

  DirectoryStatistics statistics(TenantId tenantId) {
    DirectoryStatistics s;
    s.tenantId = tenantId;
    auto now = clock();
    auto dayAgo = now - stdTimeDay;
    int pending;

    auto policies = repos.policies.findByTenant(tenantId);
    s.passwordPolicies = cast(int) policies.length;
    PasswordPolicy policyOf(string name) {
      foreach (p; policies)
        if (name.length ? sameName(p.name, name) : p.isDefault)
          return p;
      return PasswordPolicy.init;
    }

    foreach (u; repos.users.findByTenant(tenantId)) {
      s.users++;
      final switch (u.status) {
      case UserStatus.active:
        s.usersActive++;
        break;
      case UserStatus.inactive:
        s.usersInactive++;
        break;
      case UserStatus.locked:
        s.usersLocked++;
        break;
      case UserStatus.staged, UserStatus.pending:
        s.usersStaged++;
        break;
      }
      if (u.mustChangePassword)
        s.usersMustChangePassword++;
      s.lastLoginAt = max(s.lastLoginAt, u.lastLoginAt);
      if (isUnlockDue(u, now))
        pending++;
      auto policy = policyOf(u.passwordPolicy);
      if (u.passwordSet && !u.mustChangePassword && !policy.isNull && isPasswordExpired(policy, u.passwordChangedAt, now))
        pending++;
    }
    foreach (g; repos.groups.findByTenant(tenantId)) {
      s.groups++;
      s.memberships += cast(int) g.members.length;
      if (g.groupType == GroupType.nested)
        s.groupsNested++;
      if (g.groupType == GroupType.dynamic)
        s.groupsDynamic++;
    }
    s.schemas = cast(int) repos.schemas.findByTenant(tenantId).length;
    foreach (c; repos.apiClients.findByTenant(tenantId)) {
      s.apiClients++;
      if (c.status == ApiClientStatus.active) {
        s.apiClientsActive++;
        if (c.isExpiredAt(now))
          pending++;
        else if (c.expiresAt > 0 && c.expiresAt <= now + 14 * stdTimeDay)
          s.apiClientsExpiringSoon++;
      }
    }
    foreach (e; repos.auditEvents.findByTenant(tenantId)) {
      s.auditEvents++;
      if (e.createdAt >= dayAgo) {
        s.auditEvents24h++;
        if (e.eventType == AuditEventType.loginFailure)
          s.loginFailures24h++;
      }
    }
    s.pendingHousekeeping = pending;
    return s;
  }
}
