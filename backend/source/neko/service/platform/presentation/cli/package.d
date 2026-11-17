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
module neko.service.platform.presentation.cli;

public:
  import neko.service.platform.presentation.cli.args;
  import neko.service.platform.presentation.cli.commands;
  import neko.service.platform.presentation.cli.output;
  import neko.service.platform.presentation.cli.services;
  import neko.service.platform.presentation.cli.transfers;
