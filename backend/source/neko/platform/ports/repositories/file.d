/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.file;

import neko.platform.domain;

@safe:

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

/// The account hierarchy and the service plan catalogue.
interface ILandscapeRepository {
  Landscape load();
  void saveGlobal(GlobalAccount global);
  void saveDirectory(Directory directory);
  bool removeDirectory(string key);
  void saveSubaccount(Subaccount subaccount);
  bool removeSubaccount(string key);
  void savePlan(ServicePlan plan);
  bool removePlan(string key);
}

/// Measured usage per month and site.
interface IUsageRepository {
  UsageRecord[] ofMonth(string month);
  /// Months with usage, newest first ("2026-11").
  string[] months();
  /// Merge the deltas into the stored records.
  void add(const(UsageRecord)[] deltas);
}
