/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports: driving (use cases, services) and driven (repositories, storages,
/// messaging, gateways) interfaces of the hexagon.
module neko.service.authentication.ports;

public {
  import neko.service.authentication.ports.driving;
  import neko.service.authentication.ports.gateways;
  import neko.service.authentication.ports.messaging;
  import neko.service.authentication.ports.repositories;
  import neko.service.authentication.ports.services;
  import neko.service.authentication.ports.storages;
  import neko.service.authentication.ports.usecases;
}
