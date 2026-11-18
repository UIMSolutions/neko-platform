/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Überwachungsdaten im Speicher: Ringpuffer für Traces und Messpunkte, Zähler je Tabelle.
module neko.database.persistence.storages.monitoring_store;

import neko.database.domain.types.monitoring;
import neko.database.ports.storages : IMonitoringStore;
import std.algorithm : canFind, sort;
import std.array : array;

@safe:

final class MemoryMonitoringStore : IMonitoringStore {
    private struct TenantData {
        TraceEntry[] traces; // älteste zuerst
        MetricSample[] samples;
        TableAccess[string] access;
    }

    private TenantData[string] data;
    private ulong nextId = 1;

    private ref TenantData of(string tenant) return {
        if (auto d = tenant in data)
            return *d;
        data[tenant] = TenantData.init;
        return data[tenant];
    }

    TraceEntry appendTrace(string tenant, TraceEntry entry, size_t maxEntries) {
        entry.id = nextId++;
        auto d = &of(tenant);
        d.traces ~= entry;
        if (maxEntries && d.traces.length > maxEntries)
            d.traces = d.traces[$ - maxEntries .. $].dup;
        return entry;
    }

    TraceEntry[] traces(string tenant) {
        auto d = tenant in data;
        if (d is null)
            return null;
        TraceEntry[] r;
        r.reserve(d.traces.length);
        foreach_reverse (e; d.traces)
            r ~= e;
        return r;
    }

    void clearTraces(string tenant) {
        if (auto d = tenant in data)
            d.traces = null;
    }

    void appendSample(string tenant, MetricSample sample, size_t maxSamples) {
        auto d = &of(tenant);
        d.samples ~= sample;
        if (maxSamples && d.samples.length > maxSamples)
            d.samples = d.samples[$ - maxSamples .. $].dup;
    }

    MetricSample[] samples(string tenant) {
        auto d = tenant in data;
        return d is null ? null : d.samples.dup;
    }

    void countAccess(string tenant, string table, bool write, string[] filterColumns, string time) {
        auto d = &of(tenant);
        auto a = table in d.access;
        if (a is null) {
            d.access[table] = TableAccess(table);
            a = table in d.access;
        }
        if (write)
            a.writes++;
        else
            a.reads++;
        if (filterColumns.length)
            a.filters++;
        foreach (c; filterColumns)
            if (!a.filterColumns.canFind(c))
                a.filterColumns ~= c;
        a.lastAccess = time;
    }

    TableAccess[] access(string tenant) {
        auto d = tenant in data;
        if (d is null)
            return null;
        auto r = d.access.values;
        r.sort!((a, b) => a.reads + a.writes > b.reads + b.writes);
        return r;
    }

    void removeTenant(string tenant) {
        data.remove(tenant);
    }
}

unittest {
    auto s = new MemoryMonitoringStore;
    foreach (i; 0 .. 5)
        s.appendTrace("a", TraceEntry(0, "t", "u", "sql"), 3);
    auto t = s.traces("a");
    assert(t.length == 3 && t[0].id == 5 && t[2].id == 3);
    s.countAccess("a", "orders", false, ["id"], "x");
    s.countAccess("a", "orders", true, ["id", "status"], "y");
    auto a = s.access("a");
    assert(a.length == 1 && a[0].reads == 1 && a[0].writes == 1 && a[0].filters == 2 && a[0].filterColumns == ["id", "status"]);
    assert(s.traces("b").length == 0);
    s.removeTenant("a");
    assert(s.access("a").length == 0);
}
