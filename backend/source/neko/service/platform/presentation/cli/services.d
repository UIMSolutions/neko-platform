/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `services …` commands: registry and lifecycle.
module neko.service.platform.presentation.cli.services;

import neko.service.platform.domain : ValidationException;
import neko.service.platform.application.dtos;
import neko.service.platform.infrastructure.container : PlatformContainer;
import neko.service.platform.presentation.cli.args;
import neko.service.platform.presentation.cli.output;

int servicesCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "list");
  switch (sub) {
  case "list":
    output.services(c.services.list(ServiceQuery(a.opt("search"), a.opt("status"), a.opt("classification"))));
    return 0;
  case "show":
    output.service(c.services.get(a.word(2, "id")));
    return 0;
  case "register":
    if (a.opt("name").length == 0)
      throw new ValidationException("Missing option --name=");
    auto r = RegisterServiceRequest(a.opt("name"), a.opt("description"), a.opt("classification"),
      a.opt("url"), a.opt("health"), a.flag("activate"));
    output.service(c.services.register(r, actor));
    return 0;
  case "update":
    auto r = UpdateServiceRequest(a.optional("description"), a.optional("url"), a.optional("health"));
    output.service(c.services.update(a.word(2, "id"), r, actor));
    return 0;
  case "activate":
    output.service(c.services.activate(a.word(2, "id"), actor));
    return 0;
  case "suspend":
    output.service(c.services.suspend(a.word(2, "id"), actor));
    return 0;
  case "retire":
    output.service(c.services.retire(a.word(2, "id"), actor));
    return 0;
  case "check":
    output.service(c.health.check(a.word(2, "id")));
    return 0;
  case "remove":
    c.services.remove(a.word(2, "id"), actor);
    output.message("Removed.");
    return 0;
  default:
    throw new ValidationException("Unknown services command '" ~ sub ~ "'");
  }
}
