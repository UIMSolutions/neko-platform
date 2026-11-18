/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.management.ports.repositories.global_accounts;
// import neko.management.domain.entities.global_account;

import neko.management;

mixin(ShowModule!());

@safe:
/// Port: outgoing — global account persistence.
interface IGlobalAccountRepository : ITenantRepository!(GlobalAccount, GlobalAccountId) {

  GlobalAccount[] findByStatus(TenantId tenantId, GlobalAccountStatus status);
  
}
