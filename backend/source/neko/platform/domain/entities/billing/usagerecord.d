/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.entities.billing.usagerecord;

import std.algorithm : any, max;
import neko.platform.domain.entities.landscape;

@safe:

/// Usage of one subaccount in one month.
struct UsageRecord {
  /// "2026-11"
  string month;
  /// Subaccount key.
  string subaccount;
  long requests;
  long bytesOut;
  long peakStorageBytes;

  /// Add `delta` (counters add up, the storage peak is the maximum).
  void merge(const UsageRecord delta) pure nothrow {
    requests += delta.requests;
    bytesOut += delta.bytesOut;
    peakStorageBytes = max(peakStorageBytes, delta.peakStorageBytes);
  }
}
