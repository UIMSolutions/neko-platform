/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer (driving adapters).
module neko.directory.presentation;

public {
  import neko.directory.presentation.resources;
  import neko.directory.presentation.tabular;
  import neko.directory.presentation.http;
  import neko.directory.presentation.odata;
  import neko.directory.presentation.scim;
  import neko.directory.presentation.cli;
  import neko.directory.presentation.web;
  // GtkD GUI: imported explicitly by source/gui.d (only built with --config=gui)
}
