/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `users …` commands: web user accounts (also the way back in when no
/// administrator can sign in any more). Passwords come from --password= or,
/// if absent, from the first line of standard input.
module neko.platform.presentation.cli.users;

import std.stdio : stdin;
import std.algorithm : filter, map, splitter;
import std.array : array, join;
import std.string : chomp, strip, toLower;
import std.typecons : nullable;
import vibe.data.json : serializeToJson;
import neko.platform.domain : NotFoundException, ValidationException;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;

int usersCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "list");
  switch (sub) {
  case "list":
    auto all = c.users.list();
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (u; all)
      rows ~= [u.userName, u.displayName, u.roles.join(","), u.active ? "active" : "inactive", u.lastLoginAt];
    output.table(["USER", "NAME", "ROLES", "STATUS", "LAST SIGN-IN"], rows);
    return 0;
  case "add":
    CreateUserRequest r;
    r.userName = a.opt("name");
    if (r.userName.length == 0)
      throw new ValidationException("Missing option --name=");
    r.displayName = a.opt("display");
    r.email = a.opt("email");
    // --role= is the spelling from before roles could be combined
    r.roles = list(a.opt("roles", a.opt("role", "viewer")));
    r.sites = sitesOf(a.opt("sites", "all"));
    r.password = password(a);
    auto created = c.users.create(r, actor);
    output.message("Created " ~ created.userName ~ " (roles: " ~ created.roles.join(", ") ~ ").");
    return 0;
  case "passwd":
    auto user = byName(c, a.word(2, "user name"));
    c.users.resetPassword(user.id, password(a), actor);
    output.message("Password of " ~ user.userName ~ " reset. Web sessions that are already open stay valid until "
        ~ "they expire or the server restarts; deactivate the user to end them at once.");
    return 0;
  case "roles", "role":
    auto user = byName(c, a.word(2, "user name"));
    UpdateUserRequest r;
    r.roles = nullable(list(a.word(3, "roles (comma separated)")));
    auto changed = c.users.update(user.id, r, actor);
    output.message(changed.userName ~ " now has the roles " ~ changed.roles.join(", ") ~ ".");
    return 0;
  case "sites":
    auto user = byName(c, a.word(2, "user name"));
    UpdateUserRequest r;
    r.sites = nullable(sitesOf(a.word(3, "sites (comma separated, or all)")));
    auto changed = c.users.update(user.id, r, actor);
    output.message(changed.userName ~ " now works on " ~ (changed.allSites ? "every site" : changed.sites.join(", "))
        ~ ".");
    return 0;
  case "activate", "deactivate":
    auto user = byName(c, a.word(2, "user name"));
    UpdateUserRequest r;
    r.active = nullable(sub == "activate");
    c.users.update(user.id, r, actor);
    output.message(user.userName ~ (sub == "activate" ? " activated." : " deactivated."));
    return 0;
  case "remove":
    auto user = byName(c, a.word(2, "user name"));
    c.users.remove(user.id, actor);
    output.message("Removed " ~ user.userName ~ ".");
    return 0;
  default:
    throw new ValidationException("Unknown users command '" ~ sub ~ "'");
  }
}

/// "all" → [] (every site)
private string[] sitesOf(string text) {
  return text == "all" ? null : list(text);
}

private UserDto byName(PlatformContainer c, string name) {
  auto wanted = name.strip.toLower;
  foreach (u; c.users.list())
    if (u.userName == wanted)
      return u;
  throw new NotFoundException("User", name);
}

private string password(CliArgs a) {
  if (a.has("password"))
    return a.opt("password");
  auto line = stdin.readln();
  if (line is null)
    throw new ValidationException("Missing password (--password= or a line on standard input)");
  return line.chomp;
}

/// "viewer, ops" → ["viewer", "ops"]
string[] list(string text) {
  return text.splitter(',').map!(s => s.strip).filter!(s => s.length > 0).array;
}
