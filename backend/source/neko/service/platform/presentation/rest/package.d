/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// vibe.d REST interface (/rest/v1): JSON in camelCase, errors as
/// {"statusMessage": "..."} with the HTTP status of the business error.
///
///   GET    overview
///   GET    services[?search=&status=&classification=]     POST services
///   GET    services/:id    PATCH services/:id    DELETE services/:id
///   POST   services/:id/{activate,suspend,retire,check}
///   GET    transfers       GET transfers/:id     GET transfers/:id/package
///   POST   transfers/export {name,targetDomain,payload}
///   POST   transfers/import <transfer document>
module neko.service.platform.presentation.rest;

import vibe.data.json;
import vibe.http.common : HTTPMethod, HTTPStatusException;
import vibe.web.rest;
import vibe.web.common : viaBody, viaQuery;
import neko.service.platform.domain;
import neko.service.platform.application.dtos;
import neko.service.platform.ports.usecases;
import neko.service.platform.presentation.http : actorOf;

@safe:

interface IPlatformApi {
  @path("/overview") @method(HTTPMethod.GET)
  OverviewDto getOverview();

  @path("/services") @method(HTTPMethod.GET)
  ServiceDto[] getServices(@viaQuery("search") string search = "", @viaQuery("status") string status = "",
    @viaQuery("classification") string classification = "");

  @path("/services/:id") @method(HTTPMethod.GET)
  ServiceDto getService(string _id);

  @path("/services") @method(HTTPMethod.POST)
  ServiceDto postService(@viaBody() RegisterServiceRequest request, string actor = "");

  @path("/services/:id") @method(HTTPMethod.PATCH)
  ServiceDto patchService(string _id, @viaBody() UpdateServiceRequest request, string actor = "");

  @path("/services/:id") @method(HTTPMethod.DELETE)
  void deleteService(string _id, string actor = "");

  @path("/services/:id/activate") @method(HTTPMethod.POST)
  ServiceDto postActivate(string _id, string actor = "");

  @path("/services/:id/suspend") @method(HTTPMethod.POST)
  ServiceDto postSuspend(string _id, string actor = "");

  @path("/services/:id/retire") @method(HTTPMethod.POST)
  ServiceDto postRetire(string _id, string actor = "");

  @path("/services/:id/check") @method(HTTPMethod.POST)
  ServiceDto postCheck(string _id);

  @path("/transfers") @method(HTTPMethod.GET)
  TransferDto[] getTransfers();

  @path("/transfers/:id") @method(HTTPMethod.GET)
  TransferDto getTransfer(string _id);

  @path("/transfers/:id/package") @method(HTTPMethod.GET)
  Json getPackage(string _id);

  @path("/transfers/export") @method(HTTPMethod.POST)
  TransferDto postExport(@viaBody() ExportPackageRequest request, string actor = "");

  @path("/transfers/import") @method(HTTPMethod.POST)
  TransferDto postImport(@viaBody() Json document, string actor = "");
}

/// Translate business exceptions into HTTP status codes.
private auto guarded(T)(scope T delegate() @safe action) {
  try
    return action();
  catch (PlatformException e)
    throw new HTTPStatusException(e.code, e.msg);
}

class PlatformApi : IPlatformApi {
  private IManageServicesUseCase services;
  private ICheckServiceHealthUseCase health;
  private ITransferPackagesUseCase transfers;
  private IPlatformOverviewUseCase overview;

  this(IManageServicesUseCase services, ICheckServiceHealthUseCase health,
      ITransferPackagesUseCase transfers, IPlatformOverviewUseCase overview) {
    this.services = services;
    this.health = health;
    this.transfers = transfers;
    this.overview = overview;
  }

  OverviewDto getOverview() {
    return overview.overview();
  }

  ServiceDto[] getServices(string search, string status, string classification) {
    return guarded(() => services.list(ServiceQuery(search, status, classification)));
  }

  ServiceDto getService(string _id) {
    return guarded(() => services.get(_id));
  }

  @before!actorOf("actor")
  ServiceDto postService(RegisterServiceRequest request, string actor) {
    return guarded(() => services.register(request, actor));
  }

  @before!actorOf("actor")
  ServiceDto patchService(string _id, UpdateServiceRequest request, string actor) {
    return guarded(() => services.update(_id, request, actor));
  }

  @before!actorOf("actor")
  void deleteService(string _id, string actor) {
    guarded(() { services.remove(_id, actor); return true; });
  }

  @before!actorOf("actor")
  ServiceDto postActivate(string _id, string actor) {
    return guarded(() => services.activate(_id, actor));
  }

  @before!actorOf("actor")
  ServiceDto postSuspend(string _id, string actor) {
    return guarded(() => services.suspend(_id, actor));
  }

  @before!actorOf("actor")
  ServiceDto postRetire(string _id, string actor) {
    return guarded(() => services.retire(_id, actor));
  }

  ServiceDto postCheck(string _id) {
    return guarded(() => health.check(_id));
  }

  TransferDto[] getTransfers() {
    return transfers.list();
  }

  TransferDto getTransfer(string _id) {
    return guarded(() => transfers.get(_id));
  }

  Json getPackage(string _id) {
    return guarded(() => parseJsonString(transfers.document(_id)));
  }

  @before!actorOf("actor")
  TransferDto postExport(ExportPackageRequest request, string actor) {
    return guarded(() => transfers.exportPackage(request, actor));
  }

  @before!actorOf("actor")
  TransferDto postImport(Json document, string actor) {
    return guarded(() => transfers.importPackage(ImportPackageRequest(document.toString), actor));
  }
}
