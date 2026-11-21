/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.services;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

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
