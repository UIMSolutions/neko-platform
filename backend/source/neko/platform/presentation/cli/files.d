/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `files …` commands: the file libraries of the subaccounts.
module neko.platform.presentation.cli.files;

import std.array : join;
import std.conv : to;
import std.file : exists, readText, write;
import std.path : baseName;
import std.typecons : nullable;
static import std.file;
import vibe.data.json : serializeToJson;
import neko.platform.domain : ValidationException;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;
import neko.platform.presentation.cli.users : list;

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
    foreach (s; u.subaccounts)
      rows ~= [s.subaccount, s.name, s.files.to!string, byteSize(s.bytes)];
    rows ~= ["", "total", u.files.to!string, byteSize(u.bytes)];
    output.table(["SUBACCOUNT", "NAME", "FILES", "SIZE"], rows);
    output.message("Free: " ~ byteSize(u.available) ~ " (" ~ u.location ~ ")");
    return 0;
  case "add":
    auto subaccount = a.word(2, "subaccount key");
    if (a.words.length < 4)
      throw new ValidationException("Missing file path(s)");
    foreach (path; a.words[3 .. $]) {
      if (!path.exists)
        throw new ValidationException("No file " ~ path);
      UploadFileRequest r;
      r.subaccount = subaccount;
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
    // `files <subaccount>` is short for `files list <subaccount>`
    auto subaccount = sub == "list" ? a.word(2, "subaccount key") : sub;
    auto all = c.files.list(subaccount, actor);
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
