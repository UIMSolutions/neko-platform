/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases;

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

/// Sites (tenants). An actor that is a user account limited to some sites
/// only sees and changes those; creating, removing and choosing the default
/// site needs access to every site.
interface IManageSitesUseCase {
  /// The sites the actor may access, the default site first.
  SiteDto[] list(string actor);
  SiteDto get(string key, string actor);
  SiteDto create(CreateSiteRequest request, string actor);
  /// Name, host names and languages.
  SiteDto update(string key, UpdateSiteRequest request, string actor);
  /// The home page text in one language.
  SiteDto updateContent(string key, UpdateSiteContentRequest request, string actor);
  SiteDto makeDefault(string key, string actor);
  /// Not the default site, and only once it has no files and no account is
  /// limited to it.
  void remove(string key, string actor);
  /// Creates the default site if there is none (start-up); returns its key.
  string ensureDefaultSite(string name, string language);

  /// The public home page for a request: the site claiming `host`, else the
  /// default site; the language from `requestedLanguage` (?lang=), the
  /// Accept-Language header or the site default.
  SitePageDto page(string host, string requestedLanguage, string acceptLanguage);
  /// The same for a site given by key (previews).
  SitePageDto pageOf(string key, string requestedLanguage, string acceptLanguage);
}

/// The file library of each site: documents, images, audio and video.
interface IManageFilesUseCase {
  /// Newest first.
  FileDto[] list(string site, string actor);
  FileDto get(string id, string actor);
  FileDto upload(UploadFileRequest request, string actor);
  FileDto update(string id, UpdateFileRequest request, string actor);
  void remove(string id, string actor);
  /// Metadata and content of a file (for downloads by signed-in users).
  FileContent open(string id, string actor);
  /// A public file of `site`, for the public pages; false if there is none.
  bool tryOpenPublic(string site, string id, out FileContent content);
  /// Files and bytes per site (all sites), and the free space.
  StorageDto storage();
}

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

interface IBillingUseCase {
  /// "" = the current month.
  BillDto bill(string month = "");
  /// The bill as CSV (one line per subaccount and plan).
  string csv(string month = "");
}
