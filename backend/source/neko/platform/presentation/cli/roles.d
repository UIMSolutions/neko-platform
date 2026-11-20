/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `roles …` commands: roles and the access right catalogue.
module neko.platform.presentation.cli.roles;

import std.array : join;
import std.conv : to;
import std.typecons : nullable;
import vibe.data.json : serializeToJson;
import neko.platform.domain : ValidationException;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;
import neko.platform.presentation.cli.users : list;

int rolesCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "list");
  switch (sub) {
  case "list":
    auto all = c.roles.list();
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (r; all)
      rows ~= [r.name, r.label, r.members.to!string, r.builtIn ? "built-in" : "custom", r.rights.join(",")];
    output.table(["ROLE", "LABEL", "USERS", "KIND", "RIGHTS"], rows);
    return 0;
  case "rights":
    auto all = c.roles.rights();
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (r; all)
      rows ~= [r.key, r.label, r.description];
    output.table(["RIGHT", "LABEL", "ALLOWS"], rows);
    return 0;
  case "show":
    role(output, c.roles.get(a.word(2, "role name")));
    return 0;
  case "add":
    CreateRoleRequest r;
    r.name = a.opt("name");
    if (r.name.length == 0)
      throw new ValidationException("Missing option --name=");
    r.label = a.opt("label");
    r.description = a.opt("description");
    r.rights = list(a.opt("rights"));
    role(output, c.roles.create(r, actor));
    return 0;
  case "update":
    UpdateRoleRequest r;
    r.label = a.optional("label");
    r.description = a.optional("description");
    if (a.has("rights"))
      r.rights = nullable(list(a.opt("rights")));
    role(output, c.roles.update(a.word(2, "role name"), r, actor));
    return 0;
  case "remove":
    auto name = a.word(2, "role name");
    c.roles.remove(name, actor);
    output.message("Removed role " ~ name ~ ".");
    return 0;
  default:
    throw new ValidationException("Unknown roles command '" ~ sub ~ "'");
  }
}

private void role(CliOutput output, RoleDto r) {
  if (output.json) {
    output.value(serializeToJson(r));
    return;
  }
  output.table(["FIELD", "VALUE"], [
    ["Name", r.name], ["Label", r.label], ["Description", r.description],
    ["Kind", r.builtIn ? (r.locked ? "built-in, every right" : "built-in") : "custom"],
    ["Users", r.members.to!string], ["Rights", r.rights.length ? r.rights.join(", ") : "–"]
  ]);
}
