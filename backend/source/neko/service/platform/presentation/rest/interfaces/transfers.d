/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.service.platform.presentation.rest.interfaces.transfers;

import vibe.data.json : Json;
import vibe.http.common : HTTPMethod;
import vibe.web.rest;
import vibe.web.common : viaBody;
import neko.service.platform.application.dtos;
import neko.service.platform.presentation.http : actorOf;

@safe:

/// vibe.d REST interface: cross-domain transfer packages.
interface ITransfersApi {
  /// GET <restPath>transfers
  @path("/transfers") @method(HTTPMethod.GET)
  TransferDto[] getTransfers();

  /// GET <restPath>transfers/:id
  @path("/transfers/:id") @method(HTTPMethod.GET)
  TransferDto getTransfer(string _id);

  /// GET <restPath>transfers/:id/package — the transfer document of an outbound package.
  @path("/transfers/:id/package") @method(HTTPMethod.GET)
  Json getPackage(string _id);

  /// POST <restPath>transfers/export {name, targetDomain, payload}
  @path("/transfers/export") @method(HTTPMethod.POST) @before!actorOf("actor")
  TransferDto postExport(@viaBody() ExportPackageRequest request, string actor = "");

  /// POST <restPath>transfers/import <transfer document>
  @path("/transfers/import") @method(HTTPMethod.POST) @before!actorOf("actor")
  TransferDto postImport(@viaBody() Json document, string actor = "");
}
