/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.entities.billing;

/// Billing: what each subaccount used in a month and what it costs.
///
/// The platform measures usage per subaccount (requests, bytes sent, peak
/// file storage); it adds up per directory and for the global account.
/// Measured plans cost quantity × price; plans without a meter cost the
/// entitled quota × price (a fixed monthly fee). Usage recorded for
/// subaccounts that no longer exist is listed separately, unbilled.
public:
    import neko.platform.domain.entities.billing.bill;
    import neko.platform.domain.entities.billing.subaccountbill;
    import neko.platform.domain.entities.billing.chargeline;
    import neko.platform.domain.entities.billing.meterrecord;
    import neko.platform.domain.entities.billing.usagerecord;