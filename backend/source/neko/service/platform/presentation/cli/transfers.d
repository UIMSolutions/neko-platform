/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `transfers …` commands: cross-domain export and import packages.
module neko.platform.presentation.cli.transfers;

import std.file : readText, write;
import vibe.data.json : parseJsonString;
import neko.platform.domain : ValidationException;
import neko.platform.application.dtos;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;

int transfersCommand(PlatformContainer c, CliArgs a, string actor, CliOutput output) {
  auto sub = a.wordOr(1, "list");
  switch (sub) {
  case "list":
    output.transfers(c.transfers.list());
    return 0;
  case "show":
    output.transfer(c.transfers.get(a.word(2, "id")));
    return 0;
  case "export":
    if (a.has("payload") && a.has("file"))
      throw new ValidationException("Use either --payload= or --file=, not both");
    auto payload = a.has("file") ? readText(a.opt("file")) : a.opt("payload");
    auto created = c.transfers.exportPackage(ExportPackageRequest(a.opt("name"), a.opt("target"), payload), actor);
    if (a.has("out")) {
      write(a.opt("out"), c.transfers.document(created.id));
      if (!output.json)
        output.file.writeln("Transfer document written to ", a.opt("out"));
    }
    output.transfer(created);
    return 0;
  case "document":
    auto doc = c.transfers.document(a.word(2, "id"));
    if (a.has("out")) {
      write(a.opt("out"), doc);
      output.message("Transfer document written to " ~ a.opt("out"));
    } else if (output.json)
      output.value(parseJsonString(doc));
    else
      output.raw(doc);
    return 0;
  case "import":
    auto doc = readText(a.word(2, "file"));
    output.transfer(c.transfers.importPackage(ImportPackageRequest(doc), actor));
    return 0;
  default:
    throw new ValidationException("Unknown transfers command '" ~ sub ~ "'");
  }
}
