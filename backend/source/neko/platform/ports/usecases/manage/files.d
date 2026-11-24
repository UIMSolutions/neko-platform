/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.files;

import neko.platform.application.dtos;
import neko.platform.domain.entities.iprule : NetworkDecision, RequestArea;
import neko.platform.domain.entities.landscape : Landscape, RoleCollection, ServicePlan;

@safe:

/// The file library of each subaccount: documents, images, audio and
/// video. An actor sees the libraries of the subaccounts it administers or
/// belongs to (user group); global account administrators, and accounts that
/// belong to no subaccount, see every library. Libraries outside an actor's
/// reach do not exist for it.
interface IManageFilesUseCase {
  /// Newest first.
  FileDto[] list(string subaccount, string actor);
  FileDto get(string id, string actor);
  FileDto upload(UploadFileRequest request, string actor);
  FileDto update(string id, UpdateFileRequest request, string actor);
  void remove(string id, string actor);
  /// Metadata and content of a file (for downloads by signed-in users).
  FileContent open(string id, string actor);
  /// A public file of `subaccount`, for downloads without signing in; false
  /// if there is none.
  bool tryOpenPublic(string subaccount, string id, out FileContent content);
  /// Files and bytes per subaccount, and the free space.
  StorageDto storage();
  /// Keys and names of the subaccounts whose libraries `actor` may open.
  SubaccountStorageDto[] libraries(string actor);
}
