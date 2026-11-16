/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Data transfer objects: what crosses the boundary between use cases and
/// driving adapters. Plain data, serialisable by vibe.d (camelCase names).
module neko.service.platform.application.dtos;

public:
  import neko.service.platform.application.dtos.requests;
  import neko.service.platform.application.dtos.responses;
  import neko.service.platform.application.dtos.transfer_document;
