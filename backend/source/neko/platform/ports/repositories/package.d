/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories;

import neko.platform.domain;

@safe:

interface IServiceRepository {
  PlatformService[] all();
  bool tryGet(ServiceId id, out PlatformService service);
  bool tryGetByName(string name, out PlatformService service);
  /// Insert or replace.
  void save(PlatformService service);
  bool remove(ServiceId id);
}

interface ITransferRepository {
  TransferPackage[] all();
  bool tryGet(TransferId id, out TransferPackage pkg);
  /// Transfers are an audit trail: they are inserted, never deleted.
  void save(TransferPackage pkg);
}

interface IUserRepository {
  UserAccount[] all();
  bool tryGet(AccountId id, out UserAccount account);
  /// `name` in canonical (lower case) form.
  bool tryGetByName(string name, out UserAccount account);
  /// Insert or replace.
  void save(UserAccount account);
  bool remove(AccountId id);
}

interface IRoleRepository {
  Role[] all();
  /// `name` in canonical (lower case) form.
  bool tryGet(string name, out Role role);
  /// Insert or replace.
  void save(Role role);
  bool remove(string name);
}

interface ISiteRepository {
  Site[] all();
  bool tryGet(string key, out Site site);
  /// Insert or replace.
  void save(Site site);
  bool remove(string key);
}

/// Metadata of the files; the content is in an IBlobStore.
interface IFileRepository {
  StoredFile[] all();
  StoredFile[] ofSite(string site);
  bool tryGet(FileId id, out StoredFile file);
  /// Insert or replace.
  void save(StoredFile file);
  bool remove(FileId id);
}

interface IIpRuleRepository {
  IpRule[] all();
  bool tryGet(IpRuleId id, out IpRule rule);
  /// Insert or replace.
  void save(IpRule rule);
  bool remove(IpRuleId id);
}
