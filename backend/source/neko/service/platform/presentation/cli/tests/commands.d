/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// runCli end to end against an in-memory container.
module neko.platform.presentation.cli.tests.commands;

version (unittest):

import std.algorithm : canFind;
import std.stdio : File;
import vibe.data.json : parseJsonString;
import neko.platform.domain : SecurityDomain;
import neko.platform.infrastructure.configuration : PlatformConfig;
import neko.platform.infrastructure.container : buildContainer, PlatformContainer;
import neko.platform.presentation.cli.commands : runCli;

private struct Run {
  int code;
  string output;
  string errors;
}

private Run run(PlatformContainer c, string[] args...) {
  auto o = File.tmpfile(), e = File.tmpfile();
  auto code = runCli(c, args.dup, o, e);
  string slurp(File f) {
    f.flush();
    f.rewind();
    string text;
    foreach (chunk; f.byChunk(4096))
      text ~= cast(string) chunk.idup;
    return text;
  }

  return Run(code, slurp(o), slurp(e));
}

unittest {
  PlatformConfig config;
  config.storage = "memory";
  auto c = buildContainer(config, SecurityDomain.open);

  assert(run(c, "help").output.canFind("Global options"));
  assert(run(c, "bogus").code == 2);

  auto empty = run(c, "services");
  assert(empty.code == 0 && empty.output.canFind("(none)"));

  auto missing = run(c, "services", "register");
  assert(missing.code == 1 && missing.errors.canFind("--name"));

  auto created = run(c, "services", "register", "--name=billing", "--activate", "--json", "--actor=tester");
  assert(created.code == 0, created.errors);
  auto service = parseJsonString(created.output);
  assert(service["name"].get!string == "billing" && service["status"].get!string == "active");
  auto id = service["id"].get!string;

  auto table = run(c, "services", "list", "--search=bill");
  assert(table.output.canFind(id) && table.output.canFind("billing"));

  assert(run(c, "services", "show", id).output.canFind("Name            billing"));
  assert(parseJsonString(run(c, "overview", "--json").output)["serviceCount"].get!long == 1);

  auto unknown = run(c, "services", "show", "nope");
  assert(unknown.code == 1 && unknown.errors.canFind("Error (404)"));

  assert(run(c, "services", "remove", id).code == 1); // must be retired first
  assert(run(c, "services", "retire", id).output.canFind("retired"));
  assert(run(c, "services", "remove", id).output.canFind("Removed."));
  assert(run(c, "transfers", "list", "--json").output.canFind("[]"));
}
