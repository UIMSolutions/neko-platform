/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases;

import neko.platform.application.dtos;

@safe:

interface IManageServicesUseCase {
  ServiceDto[] list(ServiceQuery query);
  ServiceDto get(string id);
  ServiceDto register(RegisterServiceRequest request, string actor);
  ServiceDto update(string id, UpdateServiceRequest request, string actor);
  ServiceDto activate(string id, string actor);
  ServiceDto suspend(string id, string actor);
  ServiceDto retire(string id, string actor);
  /// Only retired services may be removed from the catalogue.
  void remove(string id, string actor);
}

interface ICheckServiceHealthUseCase {
  ServiceDto check(string id);
  /// Probe every monitored service; returns the number of services checked.
  size_t checkAll();
}

interface ITransferPackagesUseCase {
  TransferDto[] list();
  TransferDto get(string id);
  TransferDto exportPackage(ExportPackageRequest request, string actor);
  /// Imports a package. A package violating policy or integrity is recorded
  /// as "rejected" (audit trail) and a PlatformException is thrown.
  TransferDto importPackage(ImportPackageRequest request, string actor);
  /// The transfer document of an outbound package (to carry to the target).
  string document(string id);
}

interface IPlatformOverviewUseCase {
  OverviewDto overview();
}

/// Web user accounts. `actor` is the user name of the caller (audit trail).
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
