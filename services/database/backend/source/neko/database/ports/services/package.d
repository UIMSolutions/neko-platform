/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Eingehende Ports für Anwendungsdienste, die keine Anwendungsfälle im engeren Sinn sind.
module neko.database.ports.services;

import neko.database.domain;

@safe:

/// Rohdaten für Messpunkte ohne Anfrage und ohne Identität (Zeitgeber der Überwachung).
interface IStatisticsSource {
    string[] openTenants();
    TableStats[] statsOf(string tenant);
}
