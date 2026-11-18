/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Überwachung, Tracing und Workload-Management.
///
/// `MonitoredDatabases` liegt als Dekorator vor dem abgesicherten SQL-Kern: jede Anweisung jedes Adapters (REST,
/// OData, Admin-Web, Unix-Socket, Assistent) läuft hindurch. Er ordnet die Anweisung einer Workload-Klasse zu,
/// lässt sie nur innerhalb deren Grenzen zu, misst sie, schreibt Traces und zählt Zugriffe je Tabelle.
/// `MonitoringService` stellt das für die Oberflächen bereit.
module neko.database.application.services.cloud.monitoring;

import neko.database.application.services.cloud.common;
import neko.database.domain;
import neko.database.ports;
import core.time : MonoTime;
import std.algorithm : canFind, filter, map, max, min, sort;
import std.array : array;
import std.format : format;
import std.parallelism : totalCPUs;
import std.string : toLower;

@safe:

/// Messpunkte: alle 60 s einer, 1440 entsprechen 24 Stunden.
enum size_t maxSamples = 1440;

private struct Interval {
    size_t statements, errors, expensive, reads, writes;
    double totalMs = 0, maxMs = 0;
}

private struct Totals {
    size_t statements, errors, expensive, violations;
}

final class MonitoredDatabases : ISqlUseCase {
    private ISqlUseCase inner;
    private ICloudRepository repo;
    private IMonitoringStore store;
    private Principal delegate() @safe current;
    private Interval[string] intervals;
    private Totals[string] totals;
    private size_t[string] inFlight; // Schlüssel: mandant/klasse

    this(ISqlUseCase inner, ICloudRepository repo, IMonitoringStore store, Principal delegate() @safe current) {
        this.inner = inner;
        this.repo = repo;
        this.store = store;
        this.current = current;
    }

    QueryResult execute(string sql) {
        return executeIn("", sql);
    }

    QueryResult executeIn(string txId, string sql) {
        auto p = current();
        if (!p.authenticated || p.isSystem)
            return inner.executeIn(txId, sql); // der Kern lehnt ab
        auto tenant = p.tenant;
        auto state = repo.tenantState(tenant);
        auto settings = state.trace;
        auto shape = inspect(sql);
        auto classIndex = resolveWorkload(state.workloadClasses, state.workloadMappings, p.name, p.role);
        WorkloadClass wc;
        if (classIndex >= 0)
            wc = state.workloadClasses[classIndex];
        auto slot = tenant ~ "/" ~ wc.name;

        TraceEntry entry;
        entry.time = utcNow();
        entry.user = p.name;
        entry.statement = normalizeStatement(sql.length > 2000 ? sql[0 .. 2000] : sql);
        entry.verb = shape.verb;
        entry.tables = shape.tables;
        entry.workloadClass = wc.name;

        if (wc.name.length && wc.totalStatementLimit && inFlight.get(slot, 0) >= wc.totalStatementLimit) {
            auto msg = format("Workload class %s: concurrency limit of %s statements reached", wc.name,
                wc.totalStatementLimit);
            violation(tenant, settings, entry, msg);
            throw new WorkloadLimitExceeded(msg);
        }
        inFlight[slot] = inFlight.get(slot, 0) + 1;
        scope (exit)
            inFlight[slot] = inFlight[slot] - 1;

        auto started = MonoTime.currTime;
        QueryResult result;
        try
            result = inner.executeIn(txId, sql);
        catch (Exception e) {
            entry.durationMs = elapsedMs(started);
            entry.error = e.msg;
            entry.kind = "error";
            count(tenant, entry, shape, true);
            if (settings.traceErrors)
                store.appendTrace(tenant, entry, settings.maxEntries);
            throw e;
        }
        entry.durationMs = elapsedMs(started);
        entry.rows = result.rows.length;
        entry.affected = result.affected;
        count(tenant, entry, shape, false);

        if (wc.name.length && wc.statementMemoryLimitMb && resultBytes(result) > wc.statementMemoryLimitMb * 1024 * 1024) {
            auto msg = format("Workload class %s: statement memory limit of %s MB exceeded", wc.name,
                wc.statementMemoryLimitMb);
            violation(tenant, settings, entry, msg);
            throw new WorkloadLimitExceeded(msg);
        }
        if (wc.name.length && wc.statementTimeoutSeconds && entry.durationMs > wc.statementTimeoutSeconds * 1000.0)
            violation(tenant, settings, entry, format("Workload class %s: statement timeout of %s s exceeded (%.0f ms)",
                    wc.name, wc.statementTimeoutSeconds, entry.durationMs));
        immutable expensive = settings.expensiveThresholdMs && entry.durationMs >= settings.expensiveThresholdMs;
        if (expensive) {
            entry.kind = "expensive";
            intervals[tenant].expensive++;
            totals[tenant].expensive++;
            store.appendTrace(tenant, entry, settings.maxEntries);
        } else if (settings.sqlTrace) {
            entry.kind = "sql";
            store.appendTrace(tenant, entry, settings.maxEntries);
        }
        return result;
    }

    string[] listTables() {
        return inner.listTables();
    }

    void checkpoint() {
        inner.checkpoint();
    }

    void mergeDelta() {
        inner.mergeDelta();
    }

    bool mergeDeltaAsync() {
        return inner.mergeDeltaAsync();
    }

    MergeStatus mergeStatus() {
        return inner.mergeStatus();
    }

    TableStats[] stats() {
        return inner.stats();
    }

    /// Schließt das laufende Intervall jedes Mandanten mit einem Messpunkt ab (Zeitgeber, ohne Identität).
    void sample(IStatisticsSource source) {
        auto cpu = processCpuPercent();
        auto rss = residentBytes();
        foreach (tenant; source.openTenants()) {
            auto i = intervals.get(tenant, Interval.init);
            intervals[tenant] = Interval.init;
            MetricSample s;
            s.time = utcNow();
            s.statements = i.statements;
            s.errors = i.errors;
            s.expensive = i.expensive;
            s.reads = i.reads;
            s.writes = i.writes;
            s.avgMs = i.statements ? i.totalMs / i.statements : 0;
            s.maxMs = i.maxMs;
            foreach (t; source.statsOf(tenant)) {
                s.tables++;
                s.rows += t.rows;
                s.memoryBytes += estimatedBytes(t);
            }
            s.cpuPercent = cpu;
            s.residentBytes = rss;
            store.appendSample(tenant, s, maxSamples);
        }
    }

    /// Laufendes Intervall als Messpunkt, ohne es abzuschließen.
    MetricSample currentInterval(string tenant) {
        auto i = intervals.get(tenant, Interval.init);
        MetricSample s;
        s.time = utcNow();
        s.statements = i.statements;
        s.errors = i.errors;
        s.expensive = i.expensive;
        s.reads = i.reads;
        s.writes = i.writes;
        s.avgMs = i.statements ? i.totalMs / i.statements : 0;
        s.maxMs = i.maxMs;
        return s;
    }

    void totalsOf(string tenant, out size_t statements, out size_t errors, out size_t expensive, out size_t violations) {
        auto t = totals.get(tenant, Totals.init);
        statements = t.statements;
        errors = t.errors;
        expensive = t.expensive;
        violations = t.violations;
    }

    private void count(string tenant, ref const TraceEntry e, ref const StatementShape shape, bool failed) {
        if (tenant !in intervals)
            intervals[tenant] = Interval.init;
        if (tenant !in totals)
            totals[tenant] = Totals.init;
        auto i = &intervals[tenant];
        i.statements++;
        i.totalMs += e.durationMs;
        i.maxMs = max(i.maxMs, e.durationMs);
        if (shape.writes)
            i.writes++;
        else
            i.reads++;
        totals[tenant].statements++;
        if (failed) {
            i.errors++;
            totals[tenant].errors++;
            return;
        }
        foreach (t; shape.tables)
            store.countAccess(tenant, t, shape.writes, shape.filterColumns.dup, e.time);
    }

    private void violation(string tenant, TraceSettings settings, TraceEntry entry, string message) {
        if (tenant !in totals)
            totals[tenant] = Totals.init;
        totals[tenant].violations++;
        entry.kind = "violation";
        entry.error = message;
        store.appendTrace(tenant, entry, settings.maxEntries);
    }
}

private double elapsedMs(MonoTime started) {
    return (MonoTime.currTime - started).total!"usecs" / 1000.0;
}

/// Grobe Größe eines Ergebnisses: Texte mit ihrer Länge, alles andere mit 16 Byte.
size_t resultBytes(ref const QueryResult r) {
    size_t bytes;
    foreach (row; r.rows)
        foreach (v; row) {
            bytes += 16;
            if (auto s = (cast() v).peek!string)
                bytes += s.length;
        }
    return bytes;
}

// --- Prozesswerte aus /proc (Linux); anderswo 0 ---

private ulong lastCpuTicks;
private MonoTime lastCpuAt;

private double processCpuPercent() @trusted {
    version (linux) {
        import std.file : readText;
        import std.string : split, lastIndexOf;
        import std.conv : to;
        import core.sys.posix.unistd : sysconf, _SC_CLK_TCK;

        try {
            auto stat = readText("/proc/self/stat");
            auto fields = stat[stat.lastIndexOf(')') + 2 .. $].split;
            auto ticks = fields[11].to!ulong + fields[12].to!ulong; // utime, stime
            auto now = MonoTime.currTime;
            double pct = 0;
            if (lastCpuAt != MonoTime.init) {
                auto secs = (now - lastCpuAt).total!"msecs" / 1000.0;
                if (secs > 0)
                    pct = (ticks - lastCpuTicks) / cast(double) sysconf(_SC_CLK_TCK) / secs * 100 / totalCPUs;
            }
            lastCpuTicks = ticks;
            lastCpuAt = now;
            return pct;
        } catch (Exception)
            return 0;
    } else
        return 0;
}

private ulong residentBytes() @trusted {
    version (linux) {
        import std.file : readText;
        import std.string : split;
        import std.conv : to;
        import core.sys.posix.unistd : sysconf, _SC_PAGESIZE;

        try
            return readText("/proc/self/statm").split[1].to!ulong * sysconf(_SC_PAGESIZE);
        catch (Exception)
            return 0;
    } else
        return 0;
}

/// Überwachung für die Oberflächen (Recht monitor; Einstellungen mit manageWorkloads).
final class MonitoringService : IMonitoringUseCase {
    private MonitoredDatabases monitored;
    private ICloudRepository repo;
    private IMonitoringStore store;
    private CloudAudit audit;

    this(MonitoredDatabases monitored, ICloudRepository repo, IMonitoringStore store, CloudAudit audit = CloudAudit.init) {
        this.monitored = monitored;
        this.repo = repo;
        this.store = store;
        this.audit = audit;
    }

    MonitoringOverview overview(Principal actor) {
        requireTenantPermission(actor, Permission.monitor);
        MonitoringOverview o;
        o.tenant = actor.tenant;
        if (repo.hasInstance(actor.tenant)) {
            auto i = repo.instance(actor.tenant);
            o.hasInstance = true;
            o.instance = InstanceInfo(i, InstanceStatus.running, i.vcpus);
        }
        o.current = monitored.currentInterval(actor.tenant);
        o.samples = store.samples(actor.tenant);
        monitored.totalsOf(actor.tenant, o.statements, o.errors, o.expensive, o.violations);
        o.settings = repo.tenantState(actor.tenant).trace;
        auto expensive = store.traces(actor.tenant).filter!(t => t.kind == "expensive").array;
        expensive.sort!((a, b) => a.durationMs > b.durationMs);
        o.topExpensive = expensive[0 .. min(10, expensive.length)];
        o.workers = totalCPUs;
        return o;
    }

    TraceEntry[] traces(Principal actor, TraceQuery q) {
        requireTenantPermission(actor, Permission.monitor);
        TraceEntry[] r;
        foreach (t; store.traces(actor.tenant)) {
            if (q.kind.length && t.kind != q.kind)
                continue;
            if (q.user.length && t.user.toLower != q.user.toLower)
                continue;
            if (q.text.length && !t.statement.toLower.canFind(q.text.toLower) && !t.error.toLower.canFind(q.text.toLower))
                continue;
            r ~= t;
            if (q.limit && r.length >= q.limit)
                break;
        }
        return r;
    }

    TraceSettings traceSettings(Principal actor) {
        requireAnyTenantPermission(actor, Permission.monitor, Permission.manageWorkloads);
        return repo.tenantState(actor.tenant).trace;
    }

    TraceSettings configureTrace(Principal actor, TraceSettings settings) {
        requireTenantPermission(actor, Permission.manageWorkloads);
        return audit.run!TraceSettings(actor, "monitoring", "configureTrace", "",
            format("sqlTrace=%s expensiveMs=%s", settings.sqlTrace, settings.expensiveThresholdMs), () {
            if (settings.maxEntries == 0 || settings.maxEntries > 100_000)
                throw new Exception("The trace keeps between 1 and 100000 entries");
            auto s = repo.tenantState(actor.tenant);
            s.trace = settings;
            repo.saveTenantState(actor.tenant, s);
            return settings;
        });
    }

    void clearTraces(Principal actor) {
        requireTenantPermission(actor, Permission.manageWorkloads);
        audit.run!void(actor, "monitoring", "clearTraces", "", "", () { store.clearTraces(actor.tenant); });
    }

    TableAccess[] tableAccess(Principal actor) {
        requireTenantPermission(actor, Permission.monitor);
        return store.access(actor.tenant);
    }

    IssueSummary issueSummary(Principal actor) {
        requireTenantPermission(actor, Permission.monitor);
        return summarize(store.traces(actor.tenant), utcNow());
    }
}
