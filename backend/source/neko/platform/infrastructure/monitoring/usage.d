/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Usage metering for billing: requests and bytes per subaccount and month,
/// collected in memory and handed to the usage repository in batches.
module neko.platform.infrastructure.monitoring.usage;

import std.datetime.systime : SysTime;
import neko.platform.domain.entities.billing : UsageRecord;

@safe:

class UsageMeter {
  private UsageRecord[string] pending;

  /// One request billed to `subaccount`.
  void count(string subaccount, SysTime at, long bytesOut) nothrow {
    if (subaccount.length == 0)
      return;
    string month;
    try
      month = at.toUTC.toISOExtString[0 .. 7];
    catch (Exception)
      return;
    auto key = month ~ "|" ~ subaccount;
    auto p = key in pending;
    if (p is null) {
      pending[key] = UsageRecord(month, subaccount);
      p = key in pending;
    }
    p.requests++;
    p.bytesOut += bytesOut;
  }

  /// The counts since the last call (and forget them).
  UsageRecord[] drain() nothrow {
    auto result = pending.values;
    pending = null;
    return result;
  }
}

///
unittest {
  auto m = new UsageMeter;
  auto at = SysTime.fromISOExtString("2026-11-30T23:59:59Z");
  m.count("shop-prod", at, 100);
  m.count("shop-prod", at, 50);
  m.count("shop-prod", SysTime.fromISOExtString("2026-12-01T00:00:01Z"), 1);
  m.count("", at, 1);
  auto d = m.drain();
  assert(d.length == 2 && m.drain().length == 0);
  foreach (u; d)
    if (u.month == "2026-11")
      assert(u.requests == 2 && u.bytesOut == 150);
}
