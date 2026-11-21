/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.roles;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

/// Roles and the access right catalogue. An actor that is a user account
/// can only grant rights it holds itself.
interface IManageRolesUseCase {
  /// Sorted by name, each with its number of members.
  RoleDto[] list();
  RoleDto get(string name);
  /// The fixed catalogue of access rights.
  AccessRightDto[] rights();
  RoleDto create(CreateRoleRequest request, string actor);
  RoleDto update(string name, UpdateRoleRequest request, string actor);
  /// Built-in roles and roles still assigned to accounts cannot be removed.
  void remove(string name, string actor);
  /// Adds missing built-in roles (start-up). Existing ones keep their changes;
  /// they only gain rights that are new in this version.
  void ensureBuiltIns();
}
