/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.presentation.rest.interfaces.overview;

import vibe.http.common : HTTPMethod;
import vibe.web.rest;
import neko.service.platform.application.dtos;

@safe:

/// vibe.d REST interface: key figures of this platform instance.
interface IOverviewApi {
  /// GET <restPath>overview
  @path("/overview") @method(HTTPMethod.GET)
  OverviewDto getOverview();
}
