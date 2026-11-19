/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.domain.ports.repositories.log_streams;
// import neko.logging.domain.entities.log_stream;

import neko.logging;

mixin(ShowModule!());

@safe:
interface ILogStreamRepository : ITenantRepository!(LogStream, LogStreamId) {

  bool existsByName(TenantId tenantId, string name);
  LogStream findByName(TenantId tenantId, string name);
  void removeByName(TenantId tenantId, string name);

}
