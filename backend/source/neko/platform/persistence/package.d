/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Persistence layer: driven adapters for the repository and storage ports.
module neko.platform.persistence;

public:
  import neko.platform.persistence.mappers;
  import neko.platform.persistence.migrations;
  import neko.platform.persistence.records;
  import neko.platform.persistence.repositories;
  import neko.platform.persistence.storages;
