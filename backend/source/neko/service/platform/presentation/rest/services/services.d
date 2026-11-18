/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.presentation.rest.services.services;

import neko.platform.application.dtos;
import neko.platform.ports.usecases;
import neko.platform.presentation.rest.interfaces.services;
import neko.platform.presentation.rest.services.support : guarded;

@safe:

class ServicesApi : IServicesApi {
  protected IManageServicesUseCase services;
  protected ICheckServiceHealthUseCase health;

  this(IManageServicesUseCase services, ICheckServiceHealthUseCase health) {
    this.services = services;
    this.health = health;
  }

  ServiceDto[] getServices(string search, string status, string classification) {
    return guarded(() => services.list(ServiceQuery(search, status, classification)));
  }

  ServiceDto getService(string _id) {
    return guarded(() => services.get(_id));
  }

  ServiceDto postService(RegisterServiceRequest request, string actor) {
    return guarded(() => services.register(request, actor));
  }

  ServiceDto patchService(string _id, UpdateServiceRequest request, string actor) {
    return guarded(() => services.update(_id, request, actor));
  }

  void deleteService(string _id, string actor) {
    guarded(() { services.remove(_id, actor); return true; });
  }

  ServiceDto postActivate(string _id, string actor) {
    return guarded(() => services.activate(_id, actor));
  }

  ServiceDto postSuspend(string _id, string actor) {
    return guarded(() => services.suspend(_id, actor));
  }

  ServiceDto postRetire(string _id, string actor) {
    return guarded(() => services.retire(_id, actor));
  }

  ServiceDto postCheck(string _id) {
    return guarded(() => health.check(_id));
  }
}
