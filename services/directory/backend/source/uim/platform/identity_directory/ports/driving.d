/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.ports.driving;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Bundle of all driving ports. Presentation adapters (REST, OData, SCIM, CLI,
/// GUI) depend on this bundle only — never on concrete interactors or repositories.
struct DirectoryPorts {
  IManageUsersUseCase users;
  IManageGroupsUseCase groups;
  IManageSchemasUseCase schemas;
  IManagePasswordPoliciesUseCase passwordPolicies;
  IManageApiClientsUseCase apiClients;
  IAuditLogUseCase auditLog;
  IHousekeepingUseCase housekeeping;
  IDirectoryStatisticsService statistics;
  IDirectorySeedService seeder;
}
