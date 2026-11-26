/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.entities.billing.chargeline;

import std.algorithm : any, max;
import neko.platform.domain.entities.landscape;

@safe:


/// A line item for a charge in a bill.
struct ChargeLine {
  string plan;
  string unit;
  /// In billing units.
  double quantity = 0;
  double price = 0;
  double amount = 0;
  /// Entitled quota in billing units; `unlimited`; 0 = not entitled.
  long quota;
  bool entitled;
  bool overQuota;
}
