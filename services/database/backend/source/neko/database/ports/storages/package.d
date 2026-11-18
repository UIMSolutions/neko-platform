/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ausgehende Ports (Driven) für technische Ablagen: Cloud-Zustand und Überwachungsdaten.
module neko.database.ports.storages;

import neko.database.domain;
import vibe.data.json : Json;

@safe:

/// Ganzer Cloud-Zustand als JSON-Dokument (siehe persistence.mappers.cloud).
interface ICloudStateStore {
    Json load();
    void save(Json state);
}

/// Traces, Messpunkte und Zugriffszähler je Mandant. Flüchtig: nach einem Neustart beginnt die Überwachung neu.
interface IMonitoringStore {
    /// Hängt an und kürzt auf maxEntries (die ältesten fallen weg). Vergibt die Id.
    TraceEntry appendTrace(string tenant, TraceEntry entry, size_t maxEntries);
    /// Neueste zuerst.
    TraceEntry[] traces(string tenant);
    void clearTraces(string tenant);

    void appendSample(string tenant, MetricSample sample, size_t maxSamples);
    /// Älteste zuerst.
    MetricSample[] samples(string tenant);

    void countAccess(string tenant, string table, bool write, string[] filterColumns, string time);
    TableAccess[] access(string tenant);

    void removeTenant(string tenant);
}
