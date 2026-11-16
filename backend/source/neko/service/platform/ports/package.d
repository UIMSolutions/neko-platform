/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports (hexagon boundary): driving ports (usecases) and driven ports
/// (repositories, storages, messaging, gateways, application services).
module neko.service.platform.ports;

public:
  import neko.service.platform.ports.gateways;
  import neko.service.platform.ports.messaging;
  import neko.service.platform.ports.repositories;
  import neko.service.platform.ports.services;
  import neko.service.platform.ports.storages;
  import neko.service.platform.ports.usecases;
