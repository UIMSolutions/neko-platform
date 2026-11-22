/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases.manage.globalaccounts;

import neko.platform.application.dtos;
import neko.platform.domain.entities.globalaccounts : GlobalAccountEntry;

@safe:

/// The global accounts of the instance. Each is physically separate (its
/// own data directory); this registry only says which exist, where their
/// data lives and which host names select them.
interface IManageGlobalAccountsUseCase {
  /// The default global account first.
  GlobalAccountEntry[] list();
  GlobalAccountEntry get(string key);
  /// Its data directory is global-accounts/<key>; it cannot change.
  GlobalAccountEntry create(GlobalAccountEntryRequest request, string actor);
  /// Name, host names, description.
  GlobalAccountEntry update(string key, GlobalAccountEntryRequest request, string actor);
  /// Unregisters it (not the default one). Its data directory is kept: the
  /// data of a global account is never deleted by the platform.
  void remove(string key, string actor);
  /// The global account of a request: by host name, then by the
  /// X-Neko-Global-Account header, else the default one.
  GlobalAccountEntry resolve(string host, string header);
  /// Start-up: the default global account (`key`, `name`) if there is none.
  GlobalAccountEntry ensureDefault(string key, string name);
}
