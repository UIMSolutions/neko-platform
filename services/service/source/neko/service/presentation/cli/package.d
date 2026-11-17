/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Generic command line adapter (opt-in: import neko.service.presentation.cli explicitly).
///
/// ---
/// auto app = new CliApplication("uim-demo-cli", "Demo service administration");
/// registerEntityCommands(app, engine);   // list/get/create/update/delete/invoke for every entity set
/// return app.run(argv[1 .. $]);
/// ---
module neko.service.presentation.cli;

public {
  import neko.service.presentation.cli.args;
  import neko.service.presentation.cli.table;
  import neko.service.presentation.cli.app;
  import neko.service.presentation.cli.entities;
}
