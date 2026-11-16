/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Presentation layer: driving adapters (HTTP, REST, OData, web, CLI, unix socket).
module neko.service.platform.presentation;

public:
  import neko.service.platform.presentation.cli;
  import neko.service.platform.presentation.http;
  import neko.service.platform.presentation.odata;
  import neko.service.platform.presentation.rest;
  import neko.service.platform.presentation.unix;
  import neko.service.platform.presentation.web;
