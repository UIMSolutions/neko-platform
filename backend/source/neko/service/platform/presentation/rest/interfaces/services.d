/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.presentation.rest.interfaces.services;

import vibe.http.common : HTTPMethod;
import vibe.web.rest;
import vibe.web.common : viaBody, viaQuery;
import neko.service.platform.application.dtos;
import neko.service.platform.presentation.http : actorOf;

@safe:

/// vibe.d REST interface: service registry and lifecycle.
interface IServicesApi {
  /// GET <restPath>services[?search=&status=&classification=]
  @path("/services") @method(HTTPMethod.GET)
  ServiceDto[] getServices(@viaQuery("search") string search = "", @viaQuery("status") string status = "",
    @viaQuery("classification") string classification = "");

  /// GET <restPath>services/:id
  @path("/services/:id") @method(HTTPMethod.GET)
  ServiceDto getService(string _id);

  /// POST <restPath>services
  @path("/services") @method(HTTPMethod.POST) @before!actorOf("actor")
  ServiceDto postService(@viaBody() RegisterServiceRequest request, string actor = "");

  /// PATCH <restPath>services/:id
  @path("/services/:id") @method(HTTPMethod.PATCH) @before!actorOf("actor")
  ServiceDto patchService(string _id, @viaBody() UpdateServiceRequest request, string actor = "");

  /// DELETE <restPath>services/:id
  @path("/services/:id") @method(HTTPMethod.DELETE) @before!actorOf("actor")
  void deleteService(string _id, string actor = "");

  /// POST <restPath>services/:id/activate
  @path("/services/:id/activate") @method(HTTPMethod.POST) @before!actorOf("actor")
  ServiceDto postActivate(string _id, string actor = "");

  /// POST <restPath>services/:id/suspend
  @path("/services/:id/suspend") @method(HTTPMethod.POST) @before!actorOf("actor")
  ServiceDto postSuspend(string _id, string actor = "");

  /// POST <restPath>services/:id/retire
  @path("/services/:id/retire") @method(HTTPMethod.POST) @before!actorOf("actor")
  ServiceDto postRetire(string _id, string actor = "");

  /// POST <restPath>services/:id/check — probe the health endpoint now.
  @path("/services/:id/check") @method(HTTPMethod.POST)
  ServiceDto postCheck(string _id);
}
