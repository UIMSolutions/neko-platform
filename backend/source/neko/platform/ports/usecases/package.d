/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driving ports: what presentation adapters (REST, OData, CLI, web) may call.
/// Implementations throw PlatformException subclasses on business errors.
module neko.platform.ports.usecases;

public:
  import neko.platform.ports.usecases.authenticate;
  import neko.platform.ports.usecases.billing;
  import neko.platform.ports.usecases.checkservicehealth;
  import neko.platform.ports.usecases.manage;
  import neko.platform.ports.usecases.platformoverview;
  import neko.platform.ports.usecases.transferpackage;