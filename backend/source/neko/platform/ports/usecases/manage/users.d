/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.users;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

/// Web user accounts. `actor` is the user name of the caller (audit trail).
/// An actor that is a user account cannot assign roles granting rights it
/// does not hold itself, nor change accounts holding such rights.
interface IManageUsersUseCase {
  UserDto[] list();
  UserDto get(string id);
  UserDto create(CreateUserRequest request, string actor);
  UserDto update(string id, UpdateUserRequest request, string actor);
  void resetPassword(string id, string password, string actor);
  /// Requires the current password.
  void changeOwnPassword(string id, string currentPassword, string newPassword);
  /// The last active administrator cannot be removed, demoted or deactivated.
  void remove(string id, string actor);
}
