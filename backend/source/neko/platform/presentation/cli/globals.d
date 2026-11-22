/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `globals …` commands: the global accounts of the instance.
module neko.platform.presentation.cli.globals;

import std.array : join;
import vibe.data.json : serializeToJson;
import neko.platform.application.dtos : GlobalAccountEntryRequest;
import neko.platform.domain : GlobalAccountEntry, ValidationException;
import neko.platform.infrastructure.container : accountDataDir, PlatformInstance;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;
import neko.platform.presentation.cli.users : list;

int globalsCommand(PlatformInstance instance, CliArgs a, string actor, CliOutput output) {
  auto accounts = instance.accounts;
  auto sub = a.wordOr(1, "list");
  void show(GlobalAccountEntry e) {
    if (output.json)
      return output.value(serializeToJson(e));
    output.table(["FIELD", "VALUE"], [["Key", e.key], ["Name", e.name], ["Default", e.isDefault ? "yes" : "no"],
      ["Hosts", e.hosts.join(", ")], ["Data", accountDataDir(instance.config, instance.domain, e)],
      ["Description", e.description]]);
  }

  switch (sub) {
  case "list":
    auto all = accounts.list();
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (e; all)
      rows ~= [e.key ~ (e.isDefault ? " *" : ""), e.name, e.hosts.join(", "), e.dataDir.length ? e.dataDir : "."];
    output.table(["KEY", "NAME", "HOSTS", "DATA"], rows);
    return 0;
  case "show":
    show(accounts.get(a.word(2, "key")));
    return 0;
  case "add":
    auto e = accounts.create(GlobalAccountEntryRequest(a.opt("key"), a.opt("name"), list(a.opt("hosts")),
      a.opt("description")), actor);
    // set it up now: its data directory, its landscape, its first administrator
    auto c = instance.container(e.key);
    auto admin = c.authentication.ensureAdministrator(c.config.adminUser, c.config.adminPassword);
    show(e);
    if (!output.json && admin.created)
      output.message("Administrator '" ~ admin.userName ~ "'" ~ (admin.generatedPassword.length
          ? " with the generated password '" ~ admin.generatedPassword ~ "'" : " with the configured adminPassword"));
    return 0;
  case "update":
    auto key = a.word(2, "key");
    auto old = accounts.get(key);
    show(accounts.update(key, GlobalAccountEntryRequest(key, a.opt("name", old.name), a.has("hosts")
        ? list(a.opt("hosts")) : old.hosts, a.opt("description", old.description)), actor));
    return 0;
  case "remove":
    auto key = a.word(2, "key");
    auto e = accounts.get(key);
    accounts.remove(key, actor);
    output.message("Unregistered " ~ key ~ "; its data stays in " ~ accountDataDir(instance.config, instance.domain,
        e));
    return 0;
  default:
    throw new ValidationException("Unknown globals command '" ~ sub ~ "'");
  }
}
