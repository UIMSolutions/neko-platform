/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Sites — the tenants of the instance (web interface; htmx fragments).
///
///   GET  /sites                     page                           sites.read
///   GET  /sites/new                 create dialog                  sites.manage
///   POST /sites                     create                         sites.manage (+ every site)
///   GET  /sites/:key/edit           settings dialog                sites.manage
///   POST /sites/:key                name, host names, languages    sites.manage
///   GET  /sites/:key/content?lang=  content dialog                 sites.manage
///   POST /sites/:key/content        save the content of a language sites.manage
///   POST /sites/:key/default        make it the default site       sites.manage (+ every site)
///   POST /sites/:key/delete         remove                         sites.manage (+ every site)
module neko.platform.presentation.web.sites;

import std.algorithm : canFind, filter, map, splitter;
import std.array : array;
import std.string : strip;
import std.typecons : nullable;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : CreateSiteRequest, SiteDto, UpdateSiteContentRequest, UpdateSiteRequest;
import neko.platform.domain : PlatformException;
import neko.platform.ports.usecases : IManageSitesUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.support;

@safe:

/// Values of the create / settings dialog.
struct SiteForm {
  bool existing;
  string key;
  string name;
  /// One per line in the form.
  string hosts;
  string defaultLanguage = "en";
  /// Comma separated in the form.
  string languages;
  string error;
}

/// Values of the content dialog.
struct ContentForm {
  SiteDto site;
  string language;
  string title;
  string tagline;
  string body;
  string error;
}

@requiresAuth
class SitesWeb {
  private WebGuard guard;
  private IManageSitesUseCase sites;

  mixin PageAuthentication;

  this(WebGuard guard, IManageSitesUseCase sites) {
    this.guard = guard;
    this.sites = sites;
  }

  @auth(Role.sitesRead) @path("/sites")
  void getSites(PageContext page) {
    page = page.at("Sites", "sites");
    auto list = sites.list(page.user.userName);
    render!("sites.dt", page, list);
  }

  @auth(Role.sitesManage) @path("/sites/new")
  void getNew(PageContext page) {
    SiteForm form;
    render!("site_dialog.dt", page, form);
  }

  @auth(Role.sitesManage) @path("/sites")
  void postSites(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = readForm(req);
    CreateSiteRequest r;
    r.key = form.key;
    r.name = form.name;
    r.hosts = lines(form.hosts);
    r.defaultLanguage = form.defaultLanguage;
    r.languages = commaList(form.languages);
    try {
      auto created = sites.create(r, page.user.userName);
      table(res, page, "Site " ~ created.key ~ " created", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("site_dialog.dt", page, form);
    }
  }

  @auth(Role.sitesManage) @path("/sites/:key/edit")
  void getEdit(PageContext page, HTTPServerResponse res, string _key) {
    SiteDto site;
    if (!load(res, page, _key, site))
      return;
    auto form = SiteForm(true, site.key, site.name, join(site.hosts, "\n"), site.defaultLanguage,
      join(site.languages.length > 1 ? site.languages[1 .. $] : null, ", "));
    render!("site_dialog.dt", page, form);
  }

  @auth(Role.sitesManage) @path("/sites/:key")
  void postSite(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    SiteDto site;
    if (!load(res, page, _key, site))
      return;
    auto form = readForm(req);
    form.existing = true;
    form.key = site.key;
    UpdateSiteRequest r;
    r.name = nullable(form.name);
    r.hosts = nullable(lines(form.hosts));
    r.defaultLanguage = nullable(form.defaultLanguage);
    r.languages = nullable(commaList(form.languages));
    try {
      sites.update(site.key, r, page.user.userName);
      table(res, page, "Site " ~ site.key ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("site_dialog.dt", page, form);
    }
  }

  @auth(Role.sitesManage) @path("/sites/:key/content")
  void getContent(PageContext page, HTTPServerResponse res, string _key, string lang = "") {
    SiteDto site;
    if (!load(res, page, _key, site))
      return;
    auto language = site.languages.canFind(lang) ? lang : site.defaultLanguage;
    auto c = site.contentFor(language);
    auto form = ContentForm(site, language, c.title, c.tagline, c.body);
    render!("site_content_dialog.dt", page, form);
  }

  @auth(Role.sitesManage) @path("/sites/:key/content")
  void postContent(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    SiteDto site;
    if (!load(res, page, _key, site))
      return;
    auto form = ContentForm(site, req.form.get("language", ""), req.form.get("title", ""),
      req.form.get("tagline", ""), req.form.get("body", ""));
    try {
      sites.updateContent(site.key, UpdateSiteContentRequest(form.language, form.title, form.tagline, form.body),
        page.user.userName);
      table(res, page, "Content of " ~ site.key ~ " (" ~ form.language ~ ") saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("site_content_dialog.dt", page, form);
    }
  }

  @auth(Role.sitesManage) @path("/sites/:key/default")
  void postDefault(PageContext page, HTTPServerResponse res, string _key) {
    try {
      auto site = sites.makeDefault(_key, page.user.userName);
      table(res, page, site.key ~ " is now the default site", false);
    } catch (PlatformException e)
      table(res, page, e.msg, true);
  }

  @auth(Role.sitesManage) @path("/sites/:key/delete")
  void postDelete(PageContext page, HTTPServerResponse res, string _key) {
    try {
      sites.remove(_key, page.user.userName);
      table(res, page, "Site " ~ _key ~ " removed", false);
    } catch (PlatformException e)
      table(res, page, e.msg, true);
  }

  /// The refreshed site list, a toast and "close dialog".
  @noRoute void table(HTTPServerResponse res, PageContext page, string message, bool error) {
    swapTable(res, "sites-table", message, error);
    auto list = sites.list(page.user.userName);
    render!("sites_table.dt", page, list);
  }

  @noRoute bool load(HTTPServerResponse res, PageContext page, string key, out SiteDto site) {
    try {
      site = sites.get(key, page.user.userName);
      return true;
    } catch (PlatformException e) {
      table(res, page, e.msg, true);
      return false;
    }
  }
}

private SiteForm readForm(HTTPServerRequest req) {
  SiteForm form;
  form.key = req.form.get("key", "");
  form.name = req.form.get("name", "");
  form.hosts = req.form.get("hosts", "");
  form.defaultLanguage = req.form.get("defaultLanguage", "");
  form.languages = req.form.get("languages", "");
  return form;
}

/// Non-empty lines (also split at commas and spaces).
string[] lines(string text) pure {
  string[] result;
  foreach (line; text.splitter('\n'))
    foreach (part; line.splitter(','))
      foreach (word; part.splitter(' '))
        if (word.strip.length)
          result ~= word.strip;
  return result;
}

/// "de, fr  it" → ["de", "fr", "it"]
string[] commaList(string text) pure {
  return lines(text);
}

private string join(const(string)[] parts, string separator) pure {
  import std.array : join;

  return parts.join(separator);
}

///
unittest {
  assert(lines("a.example.org\r\nb.example.org, c\n\n") == ["a.example.org", "b.example.org", "c"]);
  assert(commaList("de, fr  it") == ["de", "fr", "it"]);
}
