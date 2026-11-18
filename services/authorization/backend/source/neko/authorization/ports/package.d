/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports: driving (use cases, services) and driven (repositories, storages, messaging).
module neko.authorization.ports;

public {
  import neko.authorization.ports.driving;
  import neko.authorization.ports.messaging;
  import neko.authorization.ports.repositories;
  import neko.authorization.ports.services;
  import neko.authorization.ports.storages;
  import neko.authorization.ports.usecases;
}
