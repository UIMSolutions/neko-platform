/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Server-side implementations of the REST interfaces.
module neko.platform.presentation.rest.services;

import vibe.http.router : URLRouter;
import vibe.web.rest : registerRestInterface;
import neko.platform.ports.usecases;

public:
  import neko.platform.presentation.rest.services.overview;
  import neko.platform.presentation.rest.services.services;
  import neko.platform.presentation.rest.services.support;
  import neko.platform.presentation.rest.services.transfers;

@safe:

/// Register all REST services under `restPath` (e.g. "/rest/v1/").
void registerPlatformRestApi(URLRouter router, IManageServicesUseCase services, ICheckServiceHealthUseCase health,
    ITransferPackagesUseCase transfers, IPlatformOverviewUseCase overview, string restPath) {
  router.registerRestInterface(new OverviewApi(overview), restPath);
  router.registerRestInterface(new ServicesApi(services, health), restPath);
  router.registerRestInterface(new TransfersApi(transfers), restPath);
}
