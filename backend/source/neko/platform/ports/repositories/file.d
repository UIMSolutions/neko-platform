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
