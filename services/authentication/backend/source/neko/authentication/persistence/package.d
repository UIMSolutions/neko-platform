/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Persistence layer: repository implementations (driven adapters of the
/// repository ports), storage drivers, record mappers and record schemas.
module neko.authentication.persistence;

public {
  import neko.authentication.persistence.records;
  import neko.authentication.persistence.mappers;
  import neko.authentication.persistence.storages;
  import neko.authentication.persistence.repositories;
}
