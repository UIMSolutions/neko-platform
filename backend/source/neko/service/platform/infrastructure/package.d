/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Infrastructure layer: configuration, logging, security, clients, workers
/// and the composition root.
module neko.service.platform.infrastructure;

public:
  import neko.service.platform.infrastructure.clients;
  import neko.service.platform.infrastructure.configuration;
  import neko.service.platform.infrastructure.container;
  import neko.service.platform.infrastructure.logging;
  import neko.service.platform.infrastructure.security;
  import neko.service.platform.infrastructure.workers;
