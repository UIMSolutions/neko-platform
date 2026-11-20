/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.types.language;

import std.algorithm : all, canFind, sort;
import std.array : split;
import std.ascii : isAlpha, isAlphaNum, isDigit, toLower, toUpper;
import std.conv : to;
import std.string : strip;
import neko.platform.domain.exceptions;

@safe:

/// A language tag in the BCP 47 form used on the web: a 2–3 letter language,
/// optionally a script and a region ("de", "de-CH", "zh-Hant-TW", "es-419").
/// Canonical case: language lower, script title, region upper.
struct LanguageTag {
  string value;

  this(string text) pure {
    auto parts = text.strip.split("-");
    if (parts.length == 0 || parts.length > 3)
      throw invalid(text);
    string result;
    foreach (i, part; parts) {
      if (part.length == 0 || !part.all!(c => c.isAlphaNum && c < 0x80))
        throw invalid(text);
      if (i == 0) {
        if (part.length < 2 || part.length > 3 || !part.all!isAlpha)
          throw invalid(text);
        result = lower(part);
      } else if (part.length == 4 && part.all!isAlpha)
        result ~= "-" ~ toUpper(part[0]) ~ lower(part[1 .. $]); // script
      else if ((part.length == 2 && part.all!isAlpha) || (part.length == 3 && part.all!isDigit))
        result ~= "-" ~ upper(part); // region
      else
        throw invalid(text);
    }
    value = result;
  }

  /// "de-CH" → "de"
  string primary() const pure {
    auto dash = value.length > 3 ? (value[2] == '-' ? 2 : value[3] == '-' ? 3 : value.length) : value.length;
    return value[0 .. dash];
  }

  private static ValidationException invalid(string text) pure {
    return new ValidationException("'" ~ text.strip ~ "' is not a language tag (e.g. en, de, de-CH, pt-BR)");
  }
}

private string lower(string s) pure {
  auto r = new char[s.length];
  foreach (i, c; s)
    r[i] = toLower(c);
  return r.idup;
}

private string upper(string s) pure {
  auto r = new char[s.length];
  foreach (i, c; s)
    r[i] = toUpper(c);
  return r.idup;
}

/// Pick the best of `offered` (canonical tags, preferred first) for an
/// Accept-Language header: exact matches first, then the same primary
/// language ("de-AT" → "de", "de" → "de-CH"). "" if nothing fits.
string negotiateLanguage(string acceptLanguage, const(string)[] offered) pure {
  struct Range {
    string tag;
    double q;
    size_t order;
  }

  Range[] ranges;
  foreach (i, item; acceptLanguage.split(",")) {
    auto fields = item.split(";");
    auto tag = fields.length ? fields[0].strip : "";
    double q = 1;
    foreach (p; fields.length > 1 ? fields[1 .. $] : null) {
      auto kv = p.strip;
      if (kv.length > 2 && kv[0 .. 2] == "q=")
        try
          q = kv[2 .. $].to!double;
        catch (Exception)
          q = 0;
    }
    if (tag.length && q > 0)
      ranges ~= Range(tag, q, i);
  }
  ranges.sort!((a, b) => a.q > b.q || (a.q == b.q && a.order < b.order));

  foreach (r; ranges) {
    if (r.tag == "*")
      return offered.length ? offered[0] : "";
    LanguageTag wanted;
    try
      wanted = LanguageTag(r.tag);
    catch (ValidationException)
      continue;
    if (offered.canFind(wanted.value))
      return wanted.value;
    foreach (o; offered)
      if (LanguageTag(o).primary == wanted.primary)
        return o;
  }
  return "";
}

///
unittest {
  assert(LanguageTag(" DE-ch ").value == "de-CH" && LanguageTag("de-CH").primary == "de");
  assert(LanguageTag("zh-hant-tw").value == "zh-Hant-TW" && LanguageTag("es-419").value == "es-419");
  assert(LanguageTag("fil").primary == "fil");
  foreach (bad; ["", "d", "deutsch", "de_DE", "de-", "de-12", "dé"]) {
    bool failed;
    try
      LanguageTag(bad);
    catch (ValidationException)
      failed = true;
    assert(failed, bad);
  }

  auto offered = ["en", "de-CH", "fr"];
  assert(negotiateLanguage("fr-CA,fr;q=0.9,en;q=0.8", offered) == "fr");
  assert(negotiateLanguage("de-DE,de;q=0.9", offered) == "de-CH");
  assert(negotiateLanguage("it, en;q=0.1", offered) == "en");
  assert(negotiateLanguage("it", offered) == "" && negotiateLanguage("", offered) == "");
  assert(negotiateLanguage("en;q=0.5, fr", offered) == "fr");
  assert(negotiateLanguage("*", offered) == "en");
}
