/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Command-line driving adapter. Works on the same data directory as the
/// server, so it can administer a running or a stopped instance.
///
///   args       CliArgs (positional words, --key[=value] options)
///   output     CliOutput (tables / detail views, or --json)
///   commands   runCli, usage, general commands
///   services   services …
///   transfers  transfers …
///   users      users …
module neko.platform.presentation.cli;

public:
  import neko.platform.presentation.cli.args;
  import neko.platform.presentation.cli.commands;
  import neko.platform.presentation.cli.output;
  import neko.platform.presentation.cli.roles;
  import neko.platform.presentation.cli.sites;
  import neko.platform.presentation.cli.firewall;
  import neko.platform.presentation.cli.landscape;
  import neko.platform.presentation.cli.services;
  import neko.platform.presentation.cli.transfers;
  import neko.platform.presentation.cli.users;
