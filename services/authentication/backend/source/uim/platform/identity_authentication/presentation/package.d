/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer — driving adapters: REST (http), vibe.d REST interfaces
/// (rest), OData v4 (odata), Fiori static files (web) and the CLI. The GtkD GUI
/// is imported explicitly by source/gui.d (only built with --config=gui).
module neko.service.authentication.presentation;

public {
  import neko.service.authentication.presentation.payloads;
  import neko.service.authentication.presentation.tabular;
  import neko.service.authentication.presentation.http;
  import neko.service.authentication.presentation.rest;
  import neko.service.authentication.presentation.odata;
  import neko.service.authentication.presentation.web;
  import neko.service.authentication.presentation.cli;
}
