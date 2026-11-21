/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.network;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

/// IP allow and deny lists. `actorAddress` is the address of the caller (""
/// for the CLI); a change that would lock the caller out of the management
/// pages is refused.
interface IManageNetworkUseCase {
  /// Deny rules first, then by area and network.
  IpRuleDto[] list();
  IpRuleDto add(AddIpRuleRequest request, string actor, string actorAddress);
  void remove(string id, string actor, string actorAddress);
  /// The policy for one request (cached rules; hot path of the firewall).
  NetworkDecision check(string address, RequestArea area);
  /// True if an allow rule lists the address (no rate limit, no ban).
  bool isAllowlisted(string address);
}
