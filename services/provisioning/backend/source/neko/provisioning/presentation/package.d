/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer (driving adapters).
module neko.provisioning.presentation;

public {
  import neko.provisioning.presentation.resources;
  import neko.provisioning.presentation.tabular;
  import neko.provisioning.presentation.http;
  import neko.provisioning.presentation.odata;
  import neko.provisioning.presentation.cli;
  import neko.provisioning.presentation.web;
  // GtkD GUI: imported explicitly by source/gui.d (only built with --config=gui)
}
