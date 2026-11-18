/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports: driving (use cases, services) and driven (repositories, storages,
/// messaging, gateways) interfaces of the hexagon.
module neko.authentication.ports;

public {
  import neko.authentication.ports.driving;
  import neko.authentication.ports.gateways;
  import neko.authentication.ports.messaging;
  import neko.authentication.ports.repositories;
  import neko.authentication.ports.services;
  import neko.authentication.ports.storages;
  import neko.authentication.ports.usecases;
}
