/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.transferpackage;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;
import neko.platform.application.dtos.requests;


@safe:

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

