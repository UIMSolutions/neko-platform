/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.dtos.statistics;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Aggregated figures of a tenant (Fiori KPI header, CLI "stats", GUI overview).
struct DirectoryStatistics {
  TenantId tenantId;
  int users;
  int usersActive;
  int usersInactive;
  int usersLocked;
  int usersStaged;
  int usersMustChangePassword;
  int groups;
  int groupsNested;
  int groupsDynamic;
  int memberships;
  int schemas;
  int passwordPolicies;
  int apiClients;
  int apiClientsActive;
  int apiClientsExpiringSoon;
  int auditEvents;
  int auditEvents24h;
  int loginFailures24h;
  /// Objects waiting for a time driven transition.
  int pendingHousekeeping;
  /// Most recent successful sign-in (0 = none).
  long lastLoginAt;
}

/// Outcome of one housekeeping run.
struct HousekeepingReport {
  TenantId tenantId;
  int examined;
  int changed;
  string[] changes;
}

/// Outcome of installing the predefined content.
struct SeedReport {
  TenantId tenantId;
  int created;
  int skipped;
  string[] items;
}
