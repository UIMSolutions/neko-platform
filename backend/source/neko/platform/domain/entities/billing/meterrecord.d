/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Billing: the meter for each subaccount in a month and what it costs.
module neko.platform.domain.entities.billing.meterrecord;

import std.algorithm : any, max;
import neko.platform.domain.entities.landscape;
import neko.platform.domain.entities.billing.subaccountbill;
import neko.platform.domain.entities.billing.chargeline;

@safe:

/// The complete meter for a month, including all subaccounts and unassigned usage.
struct MeterRecord {
  string month;
  SubaccountBill[] subaccountBills;
  ChargeLine[] unassignedUsage;
  double total = 0;
}
