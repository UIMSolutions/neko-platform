/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.domain.ports.usecases.pipelines;
// import neko.logging.domain.entities.pipeline;
// import neko.logging.domain.ports.repositories.pipelines;

import std.conv : ConvException, to;
import std.string : toLower;
import neko.logging;

mixin(ShowModule!());

@safe:
interface IManagePipelinesUseCase { 

  UsecaseResult createPipeline(CreatePipelineRequest req);

  UsecaseResult updatePipeline(UpdatePipelineRequest req);

  bool hasPipeline(TenantId tenantId, PipelineId id);

  Pipeline getPipeline(TenantId tenantId, PipelineId id);

  Pipeline[] listPipelines(TenantId tenantId);

  Pipeline[] listActivePipelines(TenantId tenantId);

  UsecaseResult deletePipeline(TenantId tenantId, PipelineId id);

}
