/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.ports.repositories.service;

import neko.platform.domain;

@safe:

/// Driven port for accessing and managing platform services in the repository.
interface IServiceRepository {
  PlatformService[] all();
  bool tryGet(ServiceId id, out PlatformService service);
  bool tryGetByName(string name, out PlatformService service);
  /// Insert or replace.
  void save(PlatformService service);
  bool remove(ServiceId id);
}