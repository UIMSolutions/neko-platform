/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.landscape;

import neko.platform.domain;

@safe:

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

