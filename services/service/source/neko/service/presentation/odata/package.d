/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Generic OData v4 adapter (opt-in: import neko.service.presentation.odata explicitly).
///
/// ---
/// auto engine = new ODataEngine(model).provide("Products", provider);
/// new ODataController(engine, "/odata/v4/demo").registerRoutes(router);
/// ---
module neko.service.presentation.odata;

public {
  import neko.service.presentation.odata.model;
  import neko.service.presentation.odata.query;
  import neko.service.presentation.odata.metadata;
  import neko.service.presentation.odata.resource;
  import neko.service.presentation.odata.batch;
  import neko.service.presentation.odata.engine;
  import neko.service.presentation.odata.values;
  import neko.service.presentation.odata.controller;
}
