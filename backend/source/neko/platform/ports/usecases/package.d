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
