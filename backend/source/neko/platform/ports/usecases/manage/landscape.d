/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.landscape;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

/// The account hierarchy (global account → directories → subaccounts),
/// entitlements, role collections and service plans. Every change is
/// refused if it would introduce an error into the landscape (over-assigned
/// quotas, unknown plans, duplicate subdomains, …).
interface IManageLandscapeUseCase {
  /// The tree with issues and recommendations; costs of `month` ("" = current).
  LandscapeDto overview(string month = "");
  /// "global", "directory:<key>" or "subaccount:<key>".
  NodeDto node(string node, string month = "");
  NodeDto updateGlobal(GlobalAccountRequest request, string actor);
  NodeDto saveDirectory(DirectoryRequest request, bool create, string actor);
  /// Only empty directories.
  void removeDirectory(string key, string actor);
  /// Region and subdomain cannot change after creation.
  NodeDto saveSubaccount(SubaccountRequest request, bool create, string actor);
  /// Only subaccounts without sites.
  void removeSubaccount(string key, string actor);
  /// quota: units, `unlimited` (-1) = pay per use; `remove` drops it.
  NodeDto setEntitlement(string node, string plan, long quota, bool remove, string actor);
  NodeDto saveRoleCollection(string node, RoleCollectionRequest request, string actor);
  NodeDto removeRoleCollection(string node, string name, string actor);
  ServicePlan[] plans();
  ServicePlan savePlan(ServicePlanRequest request, string actor);
  /// Only plans no node is entitled to.
  void removePlan(string key, string actor);
  /// Start-up: the global account, the default plans, and a subaccount for
  /// the default site if there is none.
  void ensureDefaults(string serviceName, string environment, string defaultSite);
  /// The raw landscape (exports).
  Landscape landscape();
}
