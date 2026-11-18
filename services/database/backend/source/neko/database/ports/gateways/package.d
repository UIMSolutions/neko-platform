/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ausgehende Ports (Driven) zu externen Systemen.
module neko.database.ports.gateways;

import neko.database.domain;

@safe:

/// Katalog der Datenprodukte, die einer Umgebung freigegeben sind (Business Data Fabric).
interface IDataProductCatalog {
    DataProduct[] products();
    /// Wirft NotFound.
    DataProduct product(string id);
}

/// Öffentliche Adresse dieses Servers (für Zugangsdaten von Bindungen).
interface IServerAddress {
    string baseUrl();
}
