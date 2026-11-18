/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// OData v4 endpoint & $metadata for SAP Fiori (generic engine of neko-services-platform:service).
module neko.authorization.presentation.odata;

public {
  import uim.platform.service.presentation.odata;
  import neko.authorization.presentation.odata.model;
  import neko.authorization.presentation.odata.errors;
  import neko.authorization.presentation.odata.serializers;
  import neko.authorization.presentation.odata.payloads;
  import neko.authorization.presentation.odata.engine;
}
