/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Intelligente Advisor: reine Funktionen über Statistik, Zugriffszählern, Messpunkten und Traces.
/// Sie ändern nichts; ausführbare Empfehlungen tragen eine SQL-Anweisung, alle anderen eine Handlungsanweisung.
///
/// - Index-Advisor: häufig gefilterte, fast eindeutige Spalten großer Tabellen und ein großer Delta-Anteil
/// - NSE-Advisor: selten genutzte, große Tabellen als Kandidaten für seitenweises Laden (PAGE LOADABLE)
/// - Partition-Advisor: Tabellen über der Zeilengrenze, Hash-Partitionierung über eine Filterspalte
/// - Performance-Class-Advisor: Speicher- und CPU-Bedarf im Analysefenster gegen Größe und Klasse
/// - ECN-Advisor: Lastspitzen lesender Anweisungen, die ein Elastic Compute Node übernehmen könnte
module neko.database.domain.services.advisors;

import neko.database.domain.entities.instance;
import neko.database.domain.enumerations.cloud;
import neko.database.domain.types.columnstats;
import neko.database.domain.types.monitoring;
import neko.database.domain.types.tablestats;
import std.algorithm : canFind, filter, map, max, maxElement, sort, sum;
import std.array : array, join;
import std.conv : to;
import std.format : format;
import std.math : ceil, sqrt;
import std.string : toLower;

@safe:

/// Schwellen der Advisor; für Tests und kleine Installationen anpassbar.
struct AdvisorSettings {
    size_t indexMinRows = 10_000;
    double indexMinCardinality = 0.3;
    double deltaShare = 0.2;
    size_t deltaMinRows = 1_000;
    ulong nseMinBytes = 1 << 20;
    double nseMaxAccessShare = 0.05;
    size_t partitionRows = 2_000_000;
    size_t maxPartitions = 64;
    size_t minSamples = 10;
    double lowUsage = 0.25, highUsage = 0.8;
    double highCpu = 70;
    double peakSigma = 2;
}

/// Alles, was die Advisor sehen.
struct AdvisorInput {
    TableStats[] stats;
    TableAccess[] access;
    MetricSample[] samples;
    TraceEntry[] traces;
    DatabaseInstance instance;
    bool hasInstance;
    string now;
}

/// Geschätzter Speicher einer Tabelle: Codes im Main, Dictionary und Delta mit 16 Byte je Wert.
ulong estimatedBytes(ref const TableStats t) {
    ulong bytes;
    foreach (c; t.columns)
        bytes += c.mainCodeBytes + (c.mainDistinct + c.deltaDistinct) * 16 + c.deltaRows * 8;
    return bytes;
}

/// Alle Advisor oder nur die in `kinds` (leer: alle).
Recommendation[] runAdvisors(AdvisorInput input, AdvisorKind[] kinds = null, AdvisorSettings s = AdvisorSettings.init) {
    bool wants(AdvisorKind k) {
        return kinds.length == 0 || kinds.canFind(k);
    }

    Recommendation[] r;
    if (wants(AdvisorKind.index))
        r ~= indexAdvisor(input, s);
    if (wants(AdvisorKind.nse))
        r ~= nseAdvisor(input, s);
    if (wants(AdvisorKind.partition))
        r ~= partitionAdvisor(input, s);
    if (wants(AdvisorKind.performanceClass))
        r ~= performanceClassAdvisor(input, s);
    if (wants(AdvisorKind.ecn))
        r ~= ecnAdvisor(input, s);
    foreach (ref x; r)
        x.createdAt = input.now;
    r.sort!((a, b) => a.severity > b.severity || (a.severity == b.severity && a.benefit > b.benefit));
    return r;
}

private bool accessOf(ref const AdvisorInput input, string table, out TableAccess found) {
    foreach (a; input.access)
        if (a.table == table.toLower) {
            found = TableAccess(a.table, a.reads, a.writes, a.filters, a.filterColumns.dup, a.lastAccess);
            return true;
        }
    return false;
}

Recommendation[] indexAdvisor(ref const AdvisorInput input, AdvisorSettings s) {
    Recommendation[] r;
    foreach (ref t; input.stats) {
        size_t delta;
        foreach (c; t.columns)
            delta = max(delta, c.deltaRows);
        if (t.rows >= s.deltaMinRows && delta >= t.rows * s.deltaShare)
            r ~= Recommendation("index:" ~ t.table ~ ":delta", AdvisorKind.index, Severity.medium, t.table,
                "Merge the delta of " ~ t.table,
                format("%s of %s rows of %s are in the delta store. Lookups scan the delta row by row; "
                    ~ "a delta merge moves them into the compressed, dictionary-encoded main store.", delta, t.rows, t.table),
                "Run a delta merge (POST /api/v1/merge, \\merge in hdb-cli or the Statistics page)", false,
                0.5 + 0.5 * (cast(double) delta / max(1, t.rows)));
        if (t.rows < s.indexMinRows)
            continue;
        TableAccess a;
        if (!accessOf(input, t.table, a))
            continue;
        foreach (ref c; t.columns) {
            if (!a.filterColumns.canFind(c.name.toLower))
                continue;
            immutable card = cast(double)(c.mainDistinct + c.deltaDistinct) / max(1, t.rows);
            if (card < s.indexMinCardinality)
                continue;
            r ~= Recommendation("index:" ~ t.table ~ ":" ~ c.name, AdvisorKind.index,
                card > 0.9 ? Severity.high : Severity.medium, t.table ~ "." ~ c.name,
                "Inverted index candidate: " ~ t.table ~ "." ~ c.name,
                format("Column %s is used in WHERE conditions of %s statements and has %.0f%% distinct values "
                    ~ "in %s rows. Point lookups on it would benefit from an inverted index.", c.name, a.filters,
                    card * 100, t.rows),
                "CREATE INVERTED INDEX IDX_" ~ t.table ~ "_" ~ c.name ~ " ON " ~ t.table ~ " (" ~ c.name ~ ")", false,
                card * (cast(double) a.filters / max(1, a.reads)));
        }
    }
    return r;
}

Recommendation[] nseAdvisor(ref const AdvisorInput input, AdvisorSettings s) {
    Recommendation[] r;
    size_t total;
    foreach (ref a; input.access)
        total += a.reads + a.writes;
    foreach (ref t; input.stats) {
        immutable bytes = estimatedBytes(t);
        if (bytes < s.nseMinBytes)
            continue;
        TableAccess a;
        immutable accesses = accessOf(input, t.table, a) ? a.reads + a.writes : 0;
        immutable share = total == 0 ? 0.0 : cast(double) accesses / total;
        if (total > 0 && share > s.nseMaxAccessShare)
            continue;
        auto enabled = !input.hasInstance || input.instance.nseEnabled;
        r ~= Recommendation("nse:" ~ t.table, AdvisorKind.nse, enabled ? Severity.medium : Severity.low, t.table,
            "Make " ~ t.table ~ " page loadable",
            format("%s holds about %s but received %.1f%% of all accesses. As a warm table it could be loaded "
                ~ "page by page instead of fully into memory.%s", t.table, humanBytes(bytes), share * 100,
                enabled ? "" : " Native Storage Extension is disabled for this instance; enable it first."),
            "ALTER TABLE " ~ t.table ~ " PAGE LOADABLE CASCADE", false, 1 - share);
    }
    return r;
}

Recommendation[] partitionAdvisor(ref const AdvisorInput input, AdvisorSettings s) {
    Recommendation[] r;
    foreach (ref t; input.stats) {
        if (t.rows < s.partitionRows || t.columns.length == 0)
            continue;
        TableAccess a;
        immutable known = accessOf(input, t.table, a);
        // Partitionsspalte: am häufigsten gefiltert und möglichst viele verschiedene Werte; sonst die erste Spalte
        string column = t.columns[0].name;
        double best = -1;
        foreach (ref c; t.columns) {
            immutable card = cast(double)(c.mainDistinct + c.deltaDistinct) / max(1, t.rows);
            immutable used = known && a.filterColumns.canFind(c.name.toLower) ? 1.0 : 0.0;
            if (used + card > best) {
                best = used + card;
                column = c.name;
            }
        }
        auto parts = cast(size_t) ceil(cast(double) t.rows / (s.partitionRows / 2));
        if (parts > s.maxPartitions)
            parts = s.maxPartitions;
        if (parts < 2)
            parts = 2;
        r ~= Recommendation("partition:" ~ t.table, AdvisorKind.partition,
            t.rows >= s.partitionRows * 4 ? Severity.high : Severity.medium, t.table, "Partition " ~ t.table,
            format("%s has %s rows. Hash partitioning on %s into %s partitions spreads merges, scans and "
                ~ "memory over smaller units.", t.table, t.rows, column, parts),
            format("ALTER TABLE %s PARTITION BY HASH (%s) PARTITIONS %s", t.table, column, parts), false,
            cast(double) t.rows / (s.partitionRows * 8));
    }
    return r;
}

Recommendation[] performanceClassAdvisor(ref const AdvisorInput input, AdvisorSettings s) {
    if (!input.hasInstance || input.samples.length < s.minSamples)
        return null;
    auto i = input.instance;
    immutable capacity = cast(double) i.memoryGb * (1UL << 30);
    // Arbeitsspeicher: Daten plus ebenso viel für Zwischenergebnisse
    immutable peak = input.samples.map!(x => cast(double) x.memoryBytes).maxElement * 2;
    immutable usage = peak / capacity;
    immutable cpu = input.samples.map!(x => x.cpuPercent).sum / input.samples.length;
    immutable window = input.samples[0].time ~ " – " ~ input.samples[$ - 1].time;
    Recommendation[] r;
    if (usage > s.highUsage) {
        auto target = roundMemory(peak / (1UL << 30) / 0.6);
        r ~= Recommendation("performanceClass:memory-up", AdvisorKind.performanceClass, Severity.high, i.name,
            format("Increase memory to %s GB", target),
            format("Peak memory demand reached %.0f%% of %s GB in %s. Size up to avoid unloads and "
                ~ "out-of-memory errors.", usage * 100, i.memoryGb, window),
            format("Resize instance %s to %s GB", i.name, target), false, usage);
    } else if (usage < s.lowUsage && i.memoryGb > minMemoryGb) {
        auto target = roundMemory(peak / (1UL << 30) / 0.6);
        if (target < i.memoryGb)
            r ~= Recommendation("performanceClass:memory-down", AdvisorKind.performanceClass, Severity.low, i.name,
                format("Reduce memory to %s GB", target),
                format("Peak memory demand was only %.1f%% of %s GB in %s. A smaller size lowers cost.",
                    usage * 100, i.memoryGb, window), format("Resize instance %s to %s GB", i.name, target), false,
                1 - usage);
    }
    if (cpu > s.highCpu && i.performanceClass != PerformanceClass.compute)
        r ~= Recommendation("performanceClass:compute", AdvisorKind.performanceClass, Severity.medium, i.name,
            "Switch to the compute performance class",
            format("Average CPU load was %.0f%% while memory usage stayed at %.0f%%. The compute class doubles "
                ~ "the vCPUs for the same memory.", cpu, usage * 100),
            "Change the performance class of " ~ i.name ~ " to compute", false, cpu / 100);
    else if (cpu < 10 && usage > 0.6 && i.performanceClass != PerformanceClass.highMemory)
        r ~= Recommendation("performanceClass:highMemory", AdvisorKind.performanceClass, Severity.low, i.name,
            "Switch to the high-memory performance class",
            format("Memory usage of %.0f%% with an average CPU load of only %.0f%%: more memory per vCPU fits "
                ~ "this workload better.", usage * 100, cpu),
            "Change the performance class of " ~ i.name ~ " to highMemory", false, usage);
    return r;
}

Recommendation[] ecnAdvisor(ref const AdvisorInput input, AdvisorSettings s) {
    if (input.samples.length < s.minSamples)
        return null;
    // Anweisungen je Stunde des Tages (UTC)
    double[24] perHour = 0;
    double[24] readsPerHour = 0;
    size_t[24] samplesPerHour;
    foreach (x; input.samples) {
        if (x.time.length < 13)
            continue;
        int h;
        try
            h = x.time[11 .. 13].to!int;
        catch (Exception)
            continue;
        perHour[h] += x.statements;
        readsPerHour[h] += x.reads;
        samplesPerHour[h]++;
    }
    double[] values;
    foreach (h; 0 .. 24)
        if (samplesPerHour[h])
            values ~= perHour[h] / samplesPerHour[h];
    if (values.length < 2)
        return null;
    immutable mean = values.sum / values.length;
    double var = 0;
    foreach (v; values)
        var += (v - mean) * (v - mean);
    immutable sigma = sqrt(var / values.length);
    Recommendation[] r;
    foreach (h; 0 .. 24) {
        if (!samplesPerHour[h])
            continue;
        immutable avg = perHour[h] / samplesPerHour[h];
        immutable readShare = perHour[h] > 0 ? readsPerHour[h] / perHour[h] : 0;
        if (sigma <= 0 || avg < mean + s.peakSigma * sigma || readShare < 0.7)
            continue;
        string[] users;
        foreach (t; input.traces)
            if (t.time.length >= 13 && t.time[11 .. 13] == format("%02d", h) && !users.canFind(t.user))
                users ~= t.user;
        auto name = input.hasInstance ? input.instance.name : "this instance";
        r ~= Recommendation(format("ecn:%02d", h), AdvisorKind.ecn,
            input.hasInstance && input.instance.ecnNodes > 0 ? Severity.info : Severity.medium, name,
            format("Route the %02d:00 UTC peak to an elastic compute node", h),
            format("Between %02d:00 and %02d:59 UTC the instance runs %.0f statements per interval, %.1f standard "
                ~ "deviations above the daily mean; %.0f%% are reads%s. An elastic compute node can take this "
                ~ "read workload without resizing the instance.", h, h, avg, (avg - mean) / sigma, readShare * 100,
                users.length ? " (mostly by " ~ users.join(", ") ~ ")" : ""),
            format("Add an elastic compute node to %s and schedule it for %02d:00–%02d:59 UTC", name, h, h), false,
            (avg - mean) / (sigma * 4));
    }
    return r;
}

string humanBytes(ulong b) {
    if (b >= 1UL << 30)
        return format("%.1f GiB", cast(double) b / (1UL << 30));
    if (b >= 1UL << 20)
        return format("%.1f MiB", cast(double) b / (1UL << 20));
    if (b >= 1UL << 10)
        return format("%.1f KiB", cast(double) b / (1UL << 10));
    return b.to!string ~ " B";
}

unittest {
    import neko.database.domain.enumerations.tablestorage : TableStorage;

    AdvisorSettings s;
    s.indexMinRows = 100;
    s.partitionRows = 1000;
    s.nseMinBytes = 100;
    s.minSamples = 3;
    AdvisorInput input;
    auto big = TableStats("orders", 5000, 0, [ColumnStats("id", 5000, 5000, 0, 5000, 0, 13, 8200),
            ColumnStats("status", 5000, 2000, 3000, 3, 3, 2, 500)], TableStorage.memory);
    auto cold = TableStats("archive", 200, 0, [ColumnStats("id", 200, 200, 0, 200, 0, 8, 200)], TableStorage.memory);
    input.stats = [big, cold];
    input.access = [TableAccess("orders", 500, 10, 300, ["id", "status"]), TableAccess("archive", 1, 0, 0, null)];
    auto r = runAdvisors(input, null, s);
    assert(r.canFind!(x => x.id == "index:orders:id"));
    assert(!r.canFind!(x => x.id == "index:orders:status")); // nur 3 verschiedene Werte
    assert(r.canFind!(x => x.id == "index:orders:delta"));
    assert(r.canFind!(x => x.id == "nse:archive") && !r.canFind!(x => x.id == "nse:orders"));
    assert(r.canFind!(x => x.id == "partition:orders" && x.action.canFind("HASH (id)")));

    input.hasInstance = true;
    input.instance = DatabaseInstance("acme");
    input.instance.memoryGb = 256;
    input.instance.storageGb = 512;
    foreach (h; 0 .. 6)
        input.samples ~= MetricSample(format("2026-11-18T%02d:00:00Z", h), h == 3 ? 900 : 10, 0, 0, 1, 2, 2, 100,
            1 << 20, 80, 0, h == 3 ? 880 : 5, 5);
    r = runAdvisors(input, [AdvisorKind.performanceClass, AdvisorKind.ecn], s);
    assert(r.canFind!(x => x.id == "performanceClass:memory-down" && x.title.canFind("16 GB")));
    assert(r.canFind!(x => x.id == "performanceClass:compute"));
    assert(r.canFind!(x => x.id == "ecn:03"));
}
