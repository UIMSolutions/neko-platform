/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for business data access, expressed in domain terms.
module neko.platform.ports.repositories.usage;

import neko.platform.domain;

@safe:

/// Measured usage per month and site.
interface IUsageRepository {
  UsageRecord[] ofMonth(string month);
  /// Months with usage, newest first ("2026-11").
  string[] months();
  /// Merge the deltas into the stored records.
  void add(const(UsageRecord)[] deltas);
}
