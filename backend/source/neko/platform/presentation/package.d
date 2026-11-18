/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer: driving adapters (HTTP, REST, OData, web, CLI, unix socket).
module neko.platform.presentation;

public:
  import neko.platform.presentation.cli;
  import neko.platform.presentation.http;
  import neko.platform.presentation.odata;
  import neko.platform.presentation.rest;
  import neko.platform.presentation.unix;
  import neko.platform.presentation.web;
