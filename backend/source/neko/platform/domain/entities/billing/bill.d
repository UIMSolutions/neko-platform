/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.entities.billing.bill;

import std.algorithm : any, max;
import neko.platform.domain.entities.landscape;
import neko.platform.domain.entities.billing.subaccountbill;
import neko.platform.domain.entities.billing.chargeline;
import neko.platform.domain.entities.billing.usagerecord;

@safe:

/// The complete bill for a month, including all subaccounts and unassigned usage.
struct Bill {
  string month;
  string currency;
  SubaccountBill[] subaccounts;
  /// Usage of subaccounts that no longer exist (not billed).
  UsageRecord[] unassigned;
  /// Directory key → total of its subtree.
  double[string] byDirectory;
  /// Plan key → total.
  double[string] byPlan;
  double total = 0;
}

Bill computeBill(const Landscape l, string month, const(UsageRecord)[] usage) pure {
  Bill bill;
  bill.month = month;
  bill.currency = l.global.currency;
  foreach (u; usage)
    if (u.month == month && !l.subaccounts.any!(s => s.key == u.subaccount))
      bill.unassigned ~= u;
  foreach (s; l.subaccounts) {
    SubaccountBill b;
    b.subaccount = s.key;
    b.costCenter = l.costCenterOf(s);
    foreach (u; usage)
      if (u.month == month && u.subaccount == s.key) {
        b.requests += u.requests;
        b.bytesOut += u.bytesOut;
        b.storageBytes += u.peakStorageBytes;
      }
    foreach (p; l.plans) {
      ChargeLine line;
      line.plan = p.key;
      line.unit = p.unit;
      line.price = p.price;
      foreach (e; s.entitlements)
        if (e.plan == p.key) {
          line.entitled = true;
          line.quota = e.quota;
        }
      final switch (p.meter) {
      case Meter.none:
        line.quantity = line.entitled && line.quota > 0 ? line.quota : 0;
        break;
      case Meter.requests:
        line.quantity = b.requests / p.unitSize;
        break;
      case Meter.egressBytes:
        line.quantity = b.bytesOut / p.unitSize;
        break;
      case Meter.storageBytes:
        line.quantity = b.storageBytes / p.unitSize;
        break;
      }
      if (!line.entitled && line.quantity == 0)
        continue;
      line.amount = line.quantity * p.price;
      line.overQuota = p.meter != Meter.none && (!line.entitled || (line.quota != unlimited && line.quantity > line.quota));
      b.lines ~= line;
      b.total += line.amount;
      bill.byPlan[p.key] = bill.byPlan.get(p.key, 0) + line.amount;
    }
    foreach (d; l.ancestors(s.directory))
      bill.byDirectory[d.key] = bill.byDirectory.get(d.key, 0) + b.total;
    bill.total += b.total;
    bill.subaccounts ~= b;
  }
  return bill;
}

///
unittest {
  import std.datetime.systime : SysTime;
  import std.math : isClose;

  Landscape l;
  l.plans = defaultPlans();
  Directory shop;
  shop.key = "shop";
  l.directories = [shop];
  Subaccount prod;
  prod.key = "shop-prod";
  prod.directory = "shop";
  prod.ensureTenancy(SysTime.init);
  prod.entitlements = [Entitlement("files.storage", 1), Entitlement("platform.requests", unlimited),
    Entitlement("support.premium", 2)];
  l.subaccounts = [prod];

  enum gib = 1024L * 1024 * 1024;
  auto usage = [UsageRecord("2026-11", "shop-prod", 120_000, 3 * gib, gib),
    UsageRecord("2026-11", "shop-prod", 30_000, 0, gib), UsageRecord("2026-10", "shop-prod", 999, 0, 0),
    UsageRecord("2026-11", "gone", 50, 1000, 0)];
  auto bill = computeBill(l, "2026-11", usage);
  auto b = bill.subaccounts[0];
  assert(b.requests == 150_000 && b.storageBytes == 2 * gib);

  double amount(string plan) {
    foreach (x; b.lines)
      if (x.plan == plan)
        return x.amount;
    return -1;
  }

  bool over(string plan) {
    foreach (x; b.lines)
      if (x.plan == plan)
        return x.overQuota;
    return false;
  }

  assert(isClose(amount("platform.requests"), 150 * 0.04) && !over("platform.requests"));
  assert(isClose(amount("network.egress"), 3 * 0.09) && over("network.egress")); // not entitled
  assert(isClose(amount("files.storage"), 2 * 0.025) && over("files.storage")); // 2 GB, quota 1
  assert(isClose(amount("support.premium"), 300.0)); // fixed fee: quota × price
  assert(isClose(bill.byDirectory["shop"], bill.total) && bill.unassigned.length == 1);

  UsageRecord r = UsageRecord("2026-11", "x", 1, 10, 5);
  r.merge(UsageRecord("2026-11", "x", 2, 5, 3));
  assert(r.requests == 3 && r.bytesOut == 15 && r.peakStorageBytes == 5);
}
