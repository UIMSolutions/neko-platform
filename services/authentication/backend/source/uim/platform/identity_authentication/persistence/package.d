/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Persistence layer: repository implementations (driven adapters of the
/// repository ports), storage drivers, record mappers and record schemas.
module neko.service.authentication.persistence;

public {
  import neko.service.authentication.persistence.records;
  import neko.service.authentication.persistence.mappers;
  import neko.service.authentication.persistence.storages;
  import neko.service.authentication.persistence.repositories;
}
