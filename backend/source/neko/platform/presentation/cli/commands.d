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
import neko.platform.infrastructure.container : PlatformContainer, PlatformInstance;
import neko.platform.presentation.cli.globals : globalsCommand;
import neko.platform.presentation.cli.args;
import neko.platform.presentation.cli.output;
import neko.platform.presentation.cli.services : servicesCommand;
import neko.platform.presentation.cli.transfers : transfersCommand;
import neko.platform.presentation.cli.roles : rolesCommand;
import neko.platform.presentation.cli.files : filesCommand;
import neko.platform.presentation.cli.firewall : firewallCommand;
import neko.platform.presentation.cli.landscape : landscapeCommand;
import neko.platform.presentation.cli.users : usersCommand;

enum usage = `Usage: platform-<domain> [command] [arguments] [--option=value …]

Global options:
  --json                              machine readable JSON output (REST field names)
  --actor=<name>                      actor recorded in the audit trail (default: cli:$USER)
  --global=<key>                      the global account to work in (default: the default one)

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
  users add --name= [--roles=viewer,…] [--display=] [--email=] [--password=]
  users passwd <name> [--password=]   reset a password (without --password: read from stdin)
  users roles <name> <role>[,<role>…] replace the roles of a user
  users activate|deactivate|remove <name>
  roles [list]                        roles and the access rights they grant
  roles show <name>
  roles rights                        the catalogue of access rights
  roles add --name= [--label=] [--description=] [--rights=status.read,…]
  roles update <name> [--label=] [--description=] [--rights=…]
  roles remove <name>                 only custom roles that no user holds
  files [list] <subaccount>           the file library of a subaccount
  files add <subaccount> <path>… [--public] [--description=]
  files get <id> [--out=]             write the content (default: the file name)
  files publish|unpublish <id>
  files remove <id>
  files usage                         files and bytes per subaccount, free space
  firewall [rules]                    the IP allow and deny lists
  firewall allow|deny <cidr> [--scope=admin|api|all] [--note=]
  firewall remove <id>
  firewall check <address>            what the IP lists decide for each area
  landscape [tree] [--month=]         global account → directories → subaccounts
  landscape show <node>               global | directory:<key> | subaccount:<key>
  landscape check                     problems and recommendations (exit 1 on errors)
  landscape billing [--month=] [--csv]
  landscape access <subaccount> [--admins=a,b] [--members=a,b] [--services=files,landscape]
  landscape tenant add|update|remove <subaccount> <tenant> [--name=] [--description=] [--default]
  landscape space add|update|remove <subaccount> <tenant> <space> [--name=] [--description=]
  landscape resolve [--host=] [--subaccount=] [--tenant=] [--space=]
                                      the tenant, space and region a service call runs in
  landscape assignments               services × subaccounts with their entitlements
  landscape assign|unassign <service> <subaccount>[,…]|all
                                      (un)assign a service, all or nothing
  landscape recovery [list]           disaster recovery of every subaccount
  landscape recovery show <subaccount>
  landscape recovery plan <subaccount> --secondary=<region> [--strategy=warm-standby] [--rpo=15] [--rto=60]
  landscape recovery plan <subaccount> --disable
  landscape recovery failover|failback <subaccount> --reason= [--minutes=]
  landscape recovery drill <subaccount> --minutes= [--failed] [--notes=]
  globals [list]                      the global accounts of this instance (physically separate)
  globals show <key>
  globals add --key= [--name=] [--hosts=a,b] [--description=]   with its own data and administrator
  globals update <key> [--name=] [--hosts=…] [--description=]
  globals remove <key>                unregister (its data directory is kept)
  help

Exit codes: 0 ok, 1 error (business errors print their HTTP-style code), 2 usage error`;

/// Run a command in the global account `--global` (default: the default
/// one); `globals …` works on the instance. Returns the process exit code.
int runCli(PlatformInstance instance, string[] args, File output = stdout, File errors = stderr) {
  auto a = CliArgs.parse(args);
  auto out_ = new CliOutput(output, a.flag("json"));
  auto actor = a.opt("actor", "cli:" ~ environment.get("USER", "unknown"));
  PlatformContainer c;
  try {
    if (a.wordOr(0, "") == "globals")
      return globalsCommand(instance, a, actor, out_);
    c = a.opt("global").length ? instance.container(a.opt("global")) : instance.defaultContainer();
  } catch (PlatformException e) {
    errors.writefln("Error (%d): %s", e.code, e.msg);
    return 1;
  } catch (Exception e) {
    errors.writeln("Error: ", e.msg);
    return 1;
  }
  return runCli(c, args, output, errors);
}

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
    case "files":
      return filesCommand(c, a, actor, out_);
    case "firewall":
      return firewallCommand(c, a, actor, out_);
    case "landscape":
      return landscapeCommand(c, a, actor, out_);
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
