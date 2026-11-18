/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Betriebsart „gateway“: ein Zugang vor mehreren hdb-Servern, Weiterleitung nach Mandant.
module neko.database.infrastructure.gateway;

public:
    import neko.database.infrastructure.gateway.proxy;
    import neko.database.infrastructure.gateway.routes;
