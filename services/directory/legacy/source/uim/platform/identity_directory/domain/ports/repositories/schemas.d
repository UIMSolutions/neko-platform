/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.ports.repositories.schemas;

// import neko.directory.domain.entities.schema;

import neko.directory;

mixin(ShowModule!());

@safe:
/// Port: outgoing — custom schema persistence.
interface ISchemaRepository : ITenantRepository!(Schema, SchemaId) {

  bool existsByName(TenantId tenantId, string name);
  Schema findByName(TenantId tenantId, string name);
  void removeByName(TenantId tenantId, string name);

}
