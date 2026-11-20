/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A site: one tenant of the platform instance, with its own host names,
/// languages, content and file library. Exactly one site is the default site:
/// it answers requests whose host name no site claims.
module neko.platform.domain.entities.site;

import std.algorithm : all, canFind, countUntil, endsWith, sort, uniq;
import std.array : array;
import std.ascii : isAlphaNum;
import std.datetime.systime : SysTime;
import std.string : strip, toLower;
import neko.platform.domain.exceptions;
import neko.platform.domain.types;

@safe:

/// The home page of a site in one language.
struct SiteContent {
  /// Canonical language tag.
  string language;
  string title;
  string tagline;
  /// Plain text; blank lines separate paragraphs.
  string body;
}

struct Site {
  SiteKey key;
  string name;
  /// Host names (lower case, without port) this site answers.
  string[] hosts;
  /// Canonical language tags; the first one is the default language.
  string[] languages;
  /// Per language. Content of a language that was removed is kept, but not
  /// shown, until the language is added again.
  SiteContent[] content;
  bool isDefault;
  SysTime createdAt;
  SysTime modifiedAt;

  string defaultLanguage() const pure nothrow {
    return languages.length ? languages[0] : "en";
  }

  void rename(string name, SysTime now) {
    auto n = name.strip;
    if (n.length == 0 || n.length > 128)
      throw new ValidationException("Site name must have 1 to 128 characters");
    this.name = n;
    modifiedAt = now;
  }

  /// Replaces the host names; ports and case are ignored.
  void setHosts(const(string)[] names, SysTime now) {
    string[] list;
    foreach (n; names) {
      if (n.strip.length == 0)
        continue;
      list ~= validHost(n);
    }
    hosts = list.sort.uniq.array;
    modifiedAt = now;
  }

  /// `defaultLanguage` first, then `others` in their order, without duplicates.
  void setLanguages(string defaultLanguage, const(string)[] others, SysTime now) {
    string[] list = [LanguageTag(defaultLanguage).value];
    foreach (o; others) {
      if (o.strip.length == 0)
        continue;
      auto tag = LanguageTag(o).value;
      if (!list.canFind(tag))
        list ~= tag;
    }
    if (list.length > 20)
      throw new ValidationException("A site can have at most 20 languages");
    languages = list;
    modifiedAt = now;
  }

  void setContent(string language, string title, string tagline, string body, SysTime now) {
    auto lang = LanguageTag(language).value;
    if (!languages.canFind(lang))
      throw new ValidationException("The site " ~ key.value ~ " has no language '" ~ lang ~ "'");
    auto t = title.strip, g = tagline.strip, b = body.strip;
    if (t.length > 160)
      throw new ValidationException("Title exceeds 160 characters");
    if (g.length > 300)
      throw new ValidationException("Tagline exceeds 300 characters");
    if (b.length > 20_000)
      throw new ValidationException("Text exceeds 20000 characters");
    auto entry = SiteContent(lang, t, g, b);
    auto i = content.countUntil!(c => c.language == lang);
    if (i < 0)
      content ~= entry;
    else
      content[i] = entry;
    modifiedAt = now;
  }

  bool hasContent(string language) const pure nothrow {
    foreach (c; content)
      if (c.language == language)
        return c.title.length > 0 || c.body.length > 0;
    return false;
  }

  /// Content in `language`; falls back to the default language, then to a
  /// title made of the site name.
  SiteContent contentFor(string language) const pure nothrow {
    if (languages.canFind(language))
      foreach (c; content)
        if (c.language == language && (c.title.length || c.body.length))
          return c;
    foreach (c; content)
      if (c.language == defaultLanguage)
        return c;
    return SiteContent(defaultLanguage, name);
  }

  /// The language to show: `requested` if the site has it, else the best
  /// match for the Accept-Language header, else the default language.
  string pickLanguage(string requested, string acceptLanguage) const pure {
    if (requested.length)
      try {
        auto tag = LanguageTag(requested).value;
        if (languages.canFind(tag))
          return tag;
      } catch (ValidationException) {
      }
    auto best = negotiateLanguage(acceptLanguage, languages);
    return best.length ? best : defaultLanguage;
  }

  bool servesHost(string host) const pure nothrow {
    return hosts.canFind(host);
  }
}

/// "Example.org:8080" → "example.org", "[::1]:8080" → "[::1]"; "" if empty.
string normalizeHost(string hostHeader) pure {
  auto h = hostHeader.strip.toLower;
  if (h.length && h[0] == '[') {
    auto close = h.countUntil(']');
    return close > 0 ? h[0 .. close + 1] : h;
  }
  auto colon = h.countUntil(':');
  if (colon >= 0)
    h = h[0 .. colon];
  while (h.endsWith("."))
    h = h[0 .. $ - 1];
  return h;
}

private string validHost(string name) pure {
  auto h = normalizeHost(name);
  if (h.length == 0 || h.length > 253 || h[0] == '.' || h[0] == '-'
      || !h.all!(c => (c.isAlphaNum && c < 0x80) || c == '.' || c == '-' || c == '[' || c == ']' || c == ':'))
    throw new ValidationException("'" ~ name.strip ~ "' is not a host name (e.g. www.example.org)");
  return h;
}

///
unittest {
  Site s;
  s.key = SiteKey("shop");
  s.rename(" Shop ", SysTime.init);
  s.setLanguages("DE", ["en", "de", "fr-ch"], SysTime.init);
  assert(s.languages == ["de", "en", "fr-CH"] && s.defaultLanguage == "de");
  s.setHosts(["Shop.Example.org:8080", "shop.example.org", "localhost", " "], SysTime.init);
  assert(s.hosts == ["localhost", "shop.example.org"] && s.servesHost("localhost"));

  assert(s.contentFor("en").title == "Shop"); // nothing written yet
  s.setContent("de", "Willkommen", "", "Absatz eins\n\nAbsatz zwei", SysTime.init);
  s.setContent("en", "Welcome", "Tagline", "", SysTime.init);
  assert(s.contentFor("en").title == "Welcome" && s.contentFor("fr-CH").title == "Willkommen");
  s.setContent("en", "Welcome!", "", "", SysTime.init);
  assert(s.content.length == 2 && s.contentFor("en").title == "Welcome!");

  assert(s.pickLanguage("EN", "") == "en" && s.pickLanguage("it", "fr-FR,fr;q=0.8") == "fr-CH");
  assert(s.pickLanguage("", "ja") == "de");

  bool failed;
  try
    s.setContent("it", "Benvenuti", "", "", SysTime.init);
  catch (ValidationException)
    failed = true;
  assert(failed);
  failed = false;
  try
    s.setHosts(["bad host"], SysTime.init);
  catch (ValidationException)
    failed = true;
  assert(failed);

  assert(normalizeHost("[::1]:8080") == "[::1]" && normalizeHost("Example.org.") == "example.org");
}
