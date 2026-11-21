/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.authenticate;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

/// Result of creating the first administrator at start-up.
struct BootstrapResult {
  bool created;
  string userName;
  /// Set when no password was configured; shown once in the log.
  string generatedPassword;
}

interface IAuthenticateUseCase {
  /// The active account with these credentials; throws AuthenticationException.
  UserDto authenticate(string userName, string password);
  /// The account behind a session, if it still exists and is active.
  bool tryActive(string id, out UserDto user);
  /// Creates an administrator if there are no accounts at all.
  BootstrapResult ensureAdministrator(string userName, string password);
}
