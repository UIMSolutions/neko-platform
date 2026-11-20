/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `firewall …` commands: the IP allow and deny lists. They work on the data
/// directory, so they also help when the web pages lock someone out; a
/// running server picks changes up within seconds.
module neko.platform.presentation.cli.firewall;

import vibe.data.json : serializeToJson;
import neko.platform.domain : ValidationException;
import neko.platform.domain.entities.iprule : RequestArea;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;

int firewallCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "rules");
  switch (sub) {
  case "rules", "list":
    auto all = c.network.list();
    if (output.json) {
      output.value(serializeToJson(all));
      return 0;
    }
    string[][] rows;
    foreach (r; all)
      rows ~= [r.id, r.action, r.network, r.scope_, r.note];
    output.table(["ID", "LIST", "NETWORK", "SCOPE", "NOTE"], rows);
    return 0;
  case "allow", "deny":
    auto r = c.network.add(AddIpRuleRequest(a.word(2, "address or network"), sub, a.opt("scope", "admin"),
      a.opt("note")), actor, "");
    output.message("Added " ~ r.network ~ " to the " ~ r.action ~ " list (" ~ r.scope_ ~ ", id " ~ r.id ~ ").");
    return 0;
  case "remove":
    auto id = a.word(2, "rule id");
    c.network.remove(id, actor, "");
    output.message("Removed IP rule " ~ id ~ ".");
    return 0;
  case "check":
    auto address = a.word(2, "address");
    string[][] rows;
    foreach (area; [RequestArea.public_, RequestArea.admin, RequestArea.api]) {
      auto d = c.network.check(address, area);
      rows ~= [area == RequestArea.public_ ? "public" : area == RequestArea.admin ? "admin" : "api",
        d.allowed ? "allowed" : "blocked", d.reason];
    }
    output.table(["AREA", "RESULT", "REASON"], rows);
    return 0;
  default:
    throw new ValidationException("Unknown firewall command '" ~ sub ~ "'");
  }
}
