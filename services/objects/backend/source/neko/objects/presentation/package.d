/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer (driving adapters).
module neko.objects.presentation;

public {
  import neko.objects.presentation.resources;
  import neko.objects.presentation.http;
  import neko.objects.presentation.odata;
  import neko.objects.presentation.cli;
  import neko.objects.presentation.web;
  import neko.objects.presentation.tabular;
  // GtkD GUI: imported explicitly by source/gui.d (only built with --config=gui)
}
