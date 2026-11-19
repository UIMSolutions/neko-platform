/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.domain.ports.usecases.retention_policies;
// import neko.logging.domain.entities.retention_policy;
// import neko.logging.domain.ports.repositories.retention_policys;
// import neko.logging.domain.services.retention_evaluator;

import neko.logging;

mixin(ShowModule!());

@safe:
interface IManageRetentionPoliciesUseCase { 
  
  UsecaseResult createRetentionPolicy(CreateRetentionPolicyRequest req);

  UsecaseResult updateRetentionPolicy(UpdateRetentionPolicyRequest req);

  RetentionPolicy getRetentionPolicy(TenantId tenantId, RetentionPolicyId id);

  RetentionPolicy[] listRetentionPolicies(TenantId tenantId);

  UsecaseResult deleteRetentionPolicy(TenantId tenantId, RetentionPolicyId policyId);

}
