/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer (driving adapters).
module neko.connectivity.presentation;

public {
  import neko.connectivity.presentation.resources;
  import neko.connectivity.presentation.tabular;
  import neko.connectivity.presentation.http;
  import neko.connectivity.presentation.odata;
  import neko.connectivity.presentation.cli;
  import neko.connectivity.presentation.web;
  // GtkD GUI: imported explicitly by source/gui.d (only built with --config=gui)
}
