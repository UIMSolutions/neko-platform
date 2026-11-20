/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Sites (multi-tenancy): host names, languages, home page content, and
/// which site the platform shows at "/".
module neko.platform.application.usecases.manage_sites;

import std.algorithm : canFind, count, filter, map, sort, sum;
import std.array : array, join;
import std.string : strip;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.application.usecases.access;
import neko.platform.ports;

@safe:

class ManageSitesUseCase : IManageSitesUseCase {
  private ISiteRepository sites;
  private IFileRepository files;
  private IUserRepository users;
  private IEventPublisher events;
  private IClock clock;

  this(ISiteRepository sites, IFileRepository files, IUserRepository users, IEventPublisher events, IClock clock) {
    this.sites = sites;
    this.files = files;
    this.users = users;
    this.events = events;
    this.clock = clock;
  }

  SiteDto[] list(string actor) {
    auto all = sites.all.filter!(s => mayAccessSite(users, actor, s.key.value)).array;
    all.sort!((a, b) => a.isDefault > b.isDefault || (a.isDefault == b.isDefault && a.key.value < b.key.value));
    auto stored = files.all;
    return all.map!(s => dto(s, stored)).array;
  }

  SiteDto get(string key, string actor) {
    auto site = load(key, actor);
    return dto(site, files.ofSite(site.key.value));
  }

  SiteDto create(CreateSiteRequest request, string actor) {
    requireAllSites(users, actor, "create sites");
    auto key = SiteKey(request.key);
    Site existing;
    if (sites.tryGet(key.value, existing))
      throw new ConflictException("A site with the key '" ~ key.value ~ "' already exists");
    auto now = clock.now;
    Site site;
    site.key = key;
    site.createdAt = now;
    site.rename(request.name.strip.length ? request.name : key.value, now);
    site.setLanguages(request.defaultLanguage.strip.length ? request.defaultLanguage : "en", request.languages, now);
    site.setHosts(request.hosts, now);
    requireFreeHosts(site);
    site.isDefault = sites.all.length == 0;
    sites.save(site);
    emit("site.created", site.key.value, actor, "Created site " ~ site.key.value ~ " (" ~ site.languages.join(", ")
        ~ (site.hosts.length ? "; " ~ site.hosts.join(", ") : "") ~ ")");
    return dto(site, null);
  }

  SiteDto update(string key, UpdateSiteRequest request, string actor) {
    auto site = load(key, actor);
    auto now = clock.now;
    if (!request.name.isNull)
      site.rename(request.name.get, now);
    if (!request.hosts.isNull) {
      site.setHosts(request.hosts.get, now);
      requireFreeHosts(site);
    }
    if (request.defaultLanguage.isNull != request.languages.isNull)
      throw new ValidationException("Set the default language and the further languages together");
    if (!request.defaultLanguage.isNull)
      site.setLanguages(request.defaultLanguage.get, request.languages.get, now);
    sites.save(site);
    emit("site.changed", site.key.value, actor, "Changed site " ~ site.key.value ~ " (" ~ site.languages.join(", ")
        ~ (site.hosts.length ? "; " ~ site.hosts.join(", ") : "") ~ ")");
    return dto(site, files.ofSite(site.key.value));
  }

  SiteDto updateContent(string key, UpdateSiteContentRequest request, string actor) {
    auto site = load(key, actor);
    site.setContent(request.language, request.title, request.tagline, request.body, clock.now);
    sites.save(site);
    emit("site.content.changed", site.key.value, actor, "Changed the " ~ LanguageTag(request.language).value
        ~ " content of site " ~ site.key.value);
    return dto(site, files.ofSite(site.key.value));
  }

  SiteDto makeDefault(string key, string actor) {
    requireAllSites(users, actor, "choose the default site");
    auto site = load(key, actor);
    auto now = clock.now;
    foreach (other; sites.all)
      if (other.isDefault && other.key != site.key) {
        other.isDefault = false;
        other.modifiedAt = now;
        sites.save(other);
      }
    site.isDefault = true;
    site.modifiedAt = now;
    sites.save(site);
    emit("site.default", site.key.value, actor, site.key.value ~ " is now the default site");
    return dto(site, files.ofSite(site.key.value));
  }

  void remove(string key, string actor) {
    requireAllSites(users, actor, "remove sites");
    auto site = load(key, actor);
    if (site.isDefault)
      throw new InvalidStateTransitionException("The default site cannot be removed; make another site the default first");
    auto stored = files.ofSite(site.key.value).length;
    if (stored > 0)
      throw new ConflictException("The site '" ~ site.key.value ~ "' still has " ~ countText(stored, "file")
          ~ "; remove them first");
    auto limited = users.all.count!(a => a.sites.canFind(site.key.value));
    if (limited > 0)
      throw new ConflictException("The site '" ~ site.key.value ~ "' is the work area of " ~ countText(limited, "account")
          ~ "; change their sites first");
    sites.remove(site.key.value);
    emit("site.removed", site.key.value, actor, "Removed site " ~ site.key.value);
  }

  string ensureDefaultSite(string name, string language) {
    auto all = sites.all;
    foreach (s; all)
      if (s.isDefault)
        return s.key.value;
    if (all.length > 0) { // e.g. the default site's document was edited by hand
      all.sort!((a, b) => a.key.value < b.key.value);
      return makeDefault(all[0].key.value, "system").key;
    }
    CreateSiteRequest r;
    r.key = "main";
    r.name = name;
    r.defaultLanguage = language;
    create(r, "system");
    auto now = clock.now;
    auto site = load("main", "system");
    site.setContent(site.defaultLanguage, name, "This is the default site of the platform.",
      "Sign in to manage sites, their languages and files.", now);
    sites.save(site);
    return site.key.value;
  }

  SitePageDto page(string host, string requestedLanguage, string acceptLanguage) {
    auto all = sites.all;
    auto h = normalizeHost(host);
    Site chosen;
    bool found;
    foreach (s; all)
      if (s.servesHost(h)) {
        chosen = s;
        found = true;
        break;
      }
    if (!found)
      foreach (s; all)
        if (s.isDefault) {
          chosen = s;
          found = true;
          break;
        }
    if (!found)
      throw new NotFoundException("Site", h);
    return pageFor(chosen, requestedLanguage, acceptLanguage);
  }

  SitePageDto pageOf(string key, string requestedLanguage, string acceptLanguage) {
    return pageFor(load(key, "system"), requestedLanguage, acceptLanguage);
  }

  private SitePageDto pageFor(const Site chosen, string requestedLanguage, string acceptLanguage) {
    SitePageDto p;
    auto stored = files.ofSite(chosen.key.value);
    p.site = dto(chosen, stored);
    p.language = chosen.pickLanguage(requestedLanguage, acceptLanguage);
    p.content = chosen.contentFor(p.language).toDto;
    stored.sort!((a, b) => a.createdAt > b.createdAt);
    foreach (f; stored.filter!(f => f.isPublic)) {
      auto d = f.toDto;
      if (f.kind == FileKind.image && f.inlineSafe)
        p.images ~= d;
      else if (f.kind == FileKind.audio || f.kind == FileKind.video)
        p.media ~= d;
      else
        p.documents ~= d;
    }
    return p;
  }

  private SiteDto dto(const Site site, const(StoredFile)[] stored) {
    long n, bytes;
    foreach (f; stored)
      if (f.site == site.key) {
        n++;
        bytes += f.size;
      }
    return site.toDto(n, bytes);
  }

  /// A host name belongs to one site only.
  private void requireFreeHosts(const Site site) {
    foreach (other; sites.all)
      if (other.key != site.key)
        foreach (h; site.hosts)
          if (other.servesHost(h))
            throw new ConflictException("The host name '" ~ h ~ "' already belongs to the site " ~ other.key.value);
  }

  private Site load(string key, string actor) {
    Site site;
    auto k = key.strip;
    if (!sites.tryGet(k, site) || !mayAccessSite(users, actor, k))
      throw new NotFoundException("Site", key);
    return site;
  }

  private void emit(string type, string subject, string actor, string message) {
    events.publish(PlatformEvent(type, subject, actor, message, clock.now));
  }
}

string countText(long n, string noun) pure {
  import std.conv : to;

  return n.to!string ~ " " ~ noun ~ (n == 1 ? "" : "s");
}
