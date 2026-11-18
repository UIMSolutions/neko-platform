/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.presentation.rest.services.transfers;

import vibe.data.json : Json, parseJsonString;
import neko.platform.application.dtos;
import neko.platform.ports.usecases;
import neko.platform.presentation.rest.interfaces.transfers;
import neko.platform.presentation.rest.services.support : guarded;

@safe:

class TransfersApi : ITransfersApi {
  protected ITransferPackagesUseCase usecase;

  this(ITransferPackagesUseCase usecase) {
    this.usecase = usecase;
  }

  TransferDto[] getTransfers() {
    return usecase.list();
  }

  TransferDto getTransfer(string _id) {
    return guarded(() => usecase.get(_id));
  }

  Json getPackage(string _id) {
    return guarded(() => parseJsonString(usecase.document(_id)));
  }

  TransferDto postExport(ExportPackageRequest request, string actor) {
    return guarded(() => usecase.exportPackage(request, actor));
  }

  TransferDto postImport(Json document, string actor) {
    return guarded(() => usecase.importPackage(ImportPackageRequest(document.toString), actor));
  }
}
