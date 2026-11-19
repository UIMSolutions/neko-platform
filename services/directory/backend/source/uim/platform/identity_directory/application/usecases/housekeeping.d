/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.housekeeping;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Interactor: time driven transitions of a tenant.
///   * locked users whose lockout expired are unlocked
///   * expired passwords must be changed at the next sign-in
///   * API clients past their expiry date are expired
///   * dynamic groups are re-evaluated
///   * audit events older than the retention period are purged
class HousekeepingUseCase : IHousekeepingUseCase {
  protected DirectoryRepositories repos;
  protected MembershipService memberships;
  protected IAuditLogUseCase auditLog;
  protected AuditTrail audit;
  protected NowFn clock;
  protected int auditRetentionDays;

  this(DirectoryRepositories repos, MembershipService memberships, IAuditLogUseCase auditLog, AuditTrail audit,
      NowFn clock, int auditRetentionDays) {
    this.repos = repos;
    this.memberships = memberships;
    this.auditLog = auditLog;
    this.audit = audit;
    this.clock = clock;
    this.auditRetentionDays = auditRetentionDays;
  }

  HousekeepingReport run(TenantId tenantId) {
    HousekeepingReport report;
    report.tenantId = tenantId;
    auto now = clock();
    auto system = UserId("system");

    void changed(string text) {
      report.changed++;
      report.changes ~= text;
    }

    auto policies = repos.policies.findByTenant(tenantId);
    PasswordPolicy policyOf(string name) {
      foreach (p; policies)
        if (name.length ? sameName(p.name, name) : p.isDefault)
          return p;
      return PasswordPolicy.init;
    }

    foreach (u; repos.users.findByTenant(tenantId)) {
      report.examined++;
      bool dirty;
      if (isUnlockDue(u, now)) {
        unlockUser(u);
        dirty = true;
        audit.record(tenantId, AuditEventType.userUnlocked, system, "User", u.id.value, u.userName, "Lockout of '" ~ u.userName ~ "' expired");
        changed("user '" ~ u.userName ~ "' unlocked (lockout expired)");
      }
      auto policy = policyOf(u.passwordPolicy);
      if (u.passwordSet && !u.mustChangePassword && !policy.isNull && isPasswordExpired(policy, u.passwordChangedAt, now)) {
        u.mustChangePassword = true;
        dirty = true;
        audit.record(tenantId, AuditEventType.passwordExpired, system, "User", u.id.value, u.userName,
          "Password of '" ~ u.userName ~ "' expired (policy '" ~ policy.name ~ "')");
        changed("password of '" ~ u.userName ~ "' expired");
      }
      if (dirty) {
        u.updatedAt = now;
        u.updatedBy = system;
        repos.users.update(u);
      }
    }

    foreach (c; repos.apiClients.findByTenant(tenantId)) {
      report.examined++;
      if (c.status == ApiClientStatus.active && c.isExpiredAt(now)) {
        c.status = ApiClientStatus.expired;
        c.updatedAt = now;
        c.updatedBy = system;
        repos.apiClients.update(c);
        audit.record(tenantId, AuditEventType.apiClientExpired, system, "ApiClient", c.id.value, c.name, "API client '" ~ c.name ~ "' expired");
        changed("API client '" ~ c.name ~ "' expired");
      }
    }

    auto dynamic = repos.groups.findMatching(tenantId, (const DirectoryGroup g) => g.groupType == GroupType.dynamic);
    report.examined += cast(int) dynamic.length;
    foreach (name; memberships.refreshDynamicGroups(tenantId))
      changed("members of dynamic group '" ~ name ~ "' updated");
    memberships.syncUsers(tenantId);

    if (auditRetentionDays > 0) {
      auto purged = auditLog.purge(tenantId, now - auditRetentionDays * stdTimeDay, system);
      if (purged.id != "0")
        changed(purged.message);
    }
    return report;
  }
}
