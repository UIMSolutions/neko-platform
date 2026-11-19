/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.infrastructure.persistence.repositories.log_streams;
// import neko.logging.domain.entities.log_stream;
// import neko.logging.domain.ports.repositories.log_streams;

import neko.logging;

mixin(ShowModule!());

@safe:
class LogStreamRepository : TenantRepository!(LogStream, LogStreamId), ILogStreamRepository {
  bool existsByName(TenantId tenantId, string name) {
    return findByTenant(tenantId).any!(s => s.name == name);
  }

  LogStream findByName(TenantId tenantId, string name) {
    foreach (s; findByTenant(tenantId))
      if (s.name == name)
        return s;
    return LogStream.init;
  }

  void removeByName(TenantId tenantId, string name) {
    remove(findByName(tenantId, name));
  }

}
