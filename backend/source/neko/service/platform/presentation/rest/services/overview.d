/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.presentation.rest.services.overview;

import neko.service.platform.application.dtos;
import neko.service.platform.ports.usecases;
import neko.service.platform.presentation.rest.interfaces.overview;

@safe:

class OverviewApi : IOverviewApi {
  protected IPlatformOverviewUseCase usecase;

  this(IPlatformOverviewUseCase usecase) {
    this.usecase = usecase;
  }

  OverviewDto getOverview() {
    return usecase.overview();
  }
}
