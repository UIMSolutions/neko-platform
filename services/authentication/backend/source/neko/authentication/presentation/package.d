/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer — driving adapters: REST (http), vibe.d REST interfaces
/// (rest), OData v4 (odata), Fiori static files (web) and the CLI. The GtkD GUI
/// is imported explicitly by source/gui.d (only built with --config=gui).
module neko.authentication.presentation;

public {
  import neko.authentication.presentation.payloads;
  import neko.authentication.presentation.tabular;
  import neko.authentication.presentation.http;
  import neko.authentication.presentation.rest;
  import neko.authentication.presentation.odata;
  import neko.authentication.presentation.web;
  import neko.authentication.presentation.cli;
}
