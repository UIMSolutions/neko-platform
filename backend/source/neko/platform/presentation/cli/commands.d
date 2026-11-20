/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// CLI entry point: usage, dispatch and the general commands. Talks to the
/// application only through the use case ports — like the HTTP adapters.
module neko.platform.presentation.cli.commands;

import std.process : environment;
import std.stdio : File, stderr, stdout;
import vibe.data.json : Json;
import neko.platform.domain : PlatformException;
import neko.platform.infrastructure.container : PlatformContainer;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;
import neko.platform.presentation.cli.services : servicesCommand;
import neko.platform.presentation.cli.transfers : transfersCommand;
import neko.platform.presentation.cli.roles : rolesCommand;
import neko.platform.presentation.cli.sites : filesCommand, sitesCommand;
import neko.platform.presentation.cli.firewall : firewallCommand;
import neko.platform.presentation.cli.users : usersCommand;

enum usage = `Usage: platform-<domain> [command] [arguments] [--option=value …]

Global options:
  --json                              machine readable JSON output (REST field names)
  --actor=<name>                      actor recorded in the audit trail (default: cli:$USER)

Commands:
  serve                               start the HTTP server (default)
  info                                show the effective configuration
  overview                            key figures of this platform instance
  services [list] [--search=] [--status=] [--classification=]
  services show <id>
  services register --name= [--description=] [--classification=] [--url=] [--health=] [--activate]
  services update <id> [--description=] [--url=] [--health=]
  services activate|suspend|retire|check|remove <id>
  check-all                           probe all active services once
  transfers [list]
  transfers show <id>
  transfers export --name= --target= (--payload= | --file=) [--out=]
  transfers document <id> [--out=]    write the transfer document of an outbound package
  transfers import <file>
  users [list]                        web user accounts of this domain
  users add --name= [--roles=viewer,…] [--sites=all|a,b] [--display=] [--email=] [--password=]
  users passwd <name> [--password=]   reset a password (without --password: read from stdin)
  users roles <name> <role>[,<role>…] replace the roles of a user
  users sites <name> all|<site>[,…]   limit a user to sites (all = every site)
  users activate|deactivate|remove <name>
  roles [list]                        roles and the access rights they grant
  roles show <name>
  roles rights                        the catalogue of access rights
  roles add --name= [--label=] [--description=] [--rights=status.read,…]
  roles update <name> [--label=] [--description=] [--rights=…]
  roles remove <name>                 only custom roles that no user holds
  sites [list]                        sites (tenants): host names, languages
  sites show <key>
  sites add --key= [--name=] [--hosts=a,b] [--language=en] [--languages=de,fr]
  sites update <key> [--name=] [--hosts=…] [--language= --languages=…]
  sites content <key> --lang= [--title=] [--tagline=] [--body= | --file=]
  sites default <key>                 show this site at / for unknown host names
  sites remove <key>                  only without files and accounts limited to it
  files [list] <site>                 the file library of a site
  files add <site> <path>… [--public] [--description=]
  files get <id> [--out=]             write the content (default: the file name)
  files publish|unpublish <id>
  files remove <id>
  files usage                         files and bytes per site, free space
  firewall [rules]                    the IP allow and deny lists
  firewall allow|deny <cidr> [--scope=admin|api|all] [--note=]
  firewall remove <id>
  firewall check <address>            what the IP lists decide for each area
  help

Exit codes: 0 ok, 1 error (business errors print their HTTP-style code), 2 usage error`;

/// Run a command; returns the process exit code.
int runCli(PlatformContainer c, string[] args, File output = stdout, File errors = stderr) {
  auto a = CliArgs.parse(args);
  auto out_ = new CliOutput(output, a.flag("json"));
  auto actor = a.opt("actor", "cli:" ~ environment.get("USER", "unknown"));
  auto command = a.wordOr(0, "help");
  try {
    switch (command) {
    case "help", "--help", "-h":
      output.writeln(usage);
      return 0;
    case "info":
      out_.value(c.config.toJson(c.domain));
      return 0;
    case "overview":
      out_.overview(c.overview.overview());
      return 0;
    case "check-all":
      auto count = c.health.checkAll();
      if (out_.json)
        out_.value(Json(["checked": Json(count)]));
      else
        output.writefln("Probed %d service(s)", count);
      return 0;
    case "services":
      return servicesCommand(c, a, actor, out_);
    case "transfers":
      return transfersCommand(c, a, actor, out_);
    case "users":
      return usersCommand(c, a, actor, out_);
    case "roles":
      return rolesCommand(c, a, actor, out_);
    case "sites":
      return sitesCommand(c, a, actor, out_);
    case "files":
      return filesCommand(c, a, actor, out_);
    case "firewall":
      return firewallCommand(c, a, actor, out_);
    default:
      errors.writeln("Unknown command '", command, "'\n\n", usage);
      return 2;
    }
  } catch (PlatformException e) {
    errors.writefln("Error (%d): %s", e.code, e.msg);
    return 1;
  } catch (Exception e) {
    errors.writeln("Error: ", e.msg);
    return 1;
  }
}
