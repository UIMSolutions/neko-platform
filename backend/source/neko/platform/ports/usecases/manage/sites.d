/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.sites;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

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

