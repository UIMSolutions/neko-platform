/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.entities.billing.subaccountbill;

import std.algorithm : any, max;
import neko.platform.domain.entities.landscape;
import neko.platform.domain.entities.billing.chargeline;

@safe:

/// A bill for one subaccount in one month.
struct SubaccountBill {
  string subaccount;
  string costCenter;
  long requests;
  long bytesOut;
  long storageBytes;
  ChargeLine[] lines;
  double total = 0;
}

