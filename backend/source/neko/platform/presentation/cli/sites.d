/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `sites …` and `files …` commands: tenants and their file libraries.
module neko.platform.presentation.cli.sites;

import std.array : join;
import std.conv : to;
import std.file : exists, readText, write;
import std.path : baseName;
import std.typecons : nullable;
import vibe.data.json : serializeToJson;
import neko.platform.domain : ValidationException;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;
import neko.platform.presentation.cli.users : list;

int sitesCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "list");
  switch (sub) {
  case "list":
    auto all = c.sites.list(actor);
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (s; all)
      rows ~= [s.key, s.name, s.isDefault ? "yes" : "", s.languages.join(","), s.hosts.join(","),
        s.files.to!string, byteSize(s.bytes)];
    output.table(["SITE", "NAME", "DEFAULT", "LANGUAGES", "HOSTS", "FILES", "SIZE"], rows);
    return 0;
  case "show":
    site(output, c.sites.get(a.word(2, "site key"), actor));
    return 0;
  case "add":
    CreateSiteRequest r;
    r.key = a.opt("key");
    if (r.key.length == 0)
      throw new ValidationException("Missing option --key=");
    r.name = a.opt("name");
    r.hosts = list(a.opt("hosts"));
    r.defaultLanguage = a.opt("language", "en");
    r.languages = list(a.opt("languages"));
    site(output, c.sites.create(r, actor));
    return 0;
  case "update":
    UpdateSiteRequest r;
    r.name = a.optional("name");
    if (a.has("hosts"))
      r.hosts = nullable(list(a.opt("hosts")));
    if (a.has("language") || a.has("languages")) {
      r.defaultLanguage = nullable(a.opt("language"));
      r.languages = nullable(list(a.opt("languages")));
    }
    site(output, c.sites.update(a.word(2, "site key"), r, actor));
    return 0;
  case "content":
    UpdateSiteContentRequest r;
    r.language = a.opt("lang");
    if (r.language.length == 0)
      throw new ValidationException("Missing option --lang=");
    r.title = a.opt("title");
    r.tagline = a.opt("tagline");
    r.body = a.has("file") ? readText(a.opt("file")) : a.opt("body");
    auto changed = c.sites.updateContent(a.word(2, "site key"), r, actor);
    output.message("Saved the " ~ r.language ~ " content of " ~ changed.key ~ ".");
    return 0;
  case "default":
    auto s = c.sites.makeDefault(a.word(2, "site key"), actor);
    output.message(s.key ~ " is now the default site.");
    return 0;
  case "remove":
    auto key = a.word(2, "site key");
    c.sites.remove(key, actor);
    output.message("Removed site " ~ key ~ ".");
    return 0;
  default:
    throw new ValidationException("Unknown sites command '" ~ sub ~ "'");
  }
}

int filesCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "list");
  switch (sub) {
  case "usage":
    auto u = c.files.storage();
    if (output.json) {
      output.value(serializeToJson(u));
      return 0;
    }
    string[][] rows;
    foreach (s; u.sites)
      rows ~= [s.site, s.name, s.files.to!string, byteSize(s.bytes)];
    rows ~= ["", "total", u.files.to!string, byteSize(u.bytes)];
    output.table(["SITE", "NAME", "FILES", "SIZE"], rows);
    output.message("Free: " ~ byteSize(u.available) ~ " (" ~ u.location ~ ")");
    return 0;
  case "add":
    auto siteKey = a.word(2, "site key");
    if (a.words.length < 4)
      throw new ValidationException("Missing file path(s)");
    foreach (path; a.words[3 .. $]) {
      if (!path.exists)
        throw new ValidationException("No file " ~ path);
      UploadFileRequest r;
      r.site = siteKey;
      r.name = path.baseName;
      r.data = cast(immutable(ubyte)[]) std.file.read(path); // the original stays where it is
      r.isPublic = a.flag("public");
      r.description = a.opt("description");
      auto f = c.files.upload(r, actor);
      output.message("Added " ~ f.name ~ " (" ~ f.id ~ ", " ~ byteSize(f.size) ~ (f.isPublic ? ", public" : "") ~ ")");
    }
    return 0;
  case "get":
    auto content = c.files.open(a.word(2, "file id"), actor);
    auto target = a.opt("out", content.file.name);
    write(target, content.localPath.length ? std.file.read(content.localPath) : cast(const(void)[]) content.data);
    output.message("Wrote " ~ target ~ " (" ~ byteSize(content.file.size) ~ ")");
    return 0;
  case "publish", "unpublish":
    UpdateFileRequest r;
    r.isPublic = nullable(sub == "publish");
    auto f = c.files.update(a.word(2, "file id"), r, actor);
    output.message(f.name ~ (f.isPublic ? " is public: " ~ f.publicUrl : " is private."));
    return 0;
  case "remove":
    auto id = a.word(2, "file id");
    c.files.remove(id, actor);
    output.message("Removed file " ~ id ~ ".");
    return 0;
  case "list":
  default:
    // `files <site>` is short for `files list <site>`
    auto siteKey = sub == "list" ? a.word(2, "site key") : sub;
    auto all = c.files.list(siteKey, actor);
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (f; all)
      rows ~= [f.id, f.name, f.kind, byteSize(f.size), f.isPublic ? "public" : "private",
        f.createdAt.length >= 16 ? f.createdAt[0 .. 10] ~ " " ~ f.createdAt[11 .. 16] : ""];
    output.table(["ID", "NAME", "KIND", "SIZE", "VISIBILITY", "UPLOADED (UTC)"], rows);
    return 0;
  }
}

private void site(CliOutput output, SiteDto s) {
  if (output.json) {
    output.value(serializeToJson(s));
    return;
  }
  string[][] rows = [
    ["Key", s.key], ["Name", s.name], ["Default site", s.isDefault ? "yes" : "no"],
    ["Host names", s.hosts.length ? s.hosts.join(", ") : "–"], ["Languages", s.languages.join(", ")],
    ["Files", s.files.to!string ~ " (" ~ byteSize(s.bytes) ~ ")"],
  ];
  foreach (lang; s.languages)
    rows ~= ["Title (" ~ lang ~ ")", s.hasContent(lang) ? s.contentFor(lang).title : "– (shows " ~ s.defaultLanguage ~ ")"];
  output.table(["FIELD", "VALUE"], rows);
}

static import std.file;
