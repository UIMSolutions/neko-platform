/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Automatische Zusammenfassung von Problemen: gruppiert Fehler und Verstöße aus dem Trace, ordnet jeder Gruppe
/// eine vermutete Ursache und eine Lösung zu und schreibt daraus einen lesbaren Text. Regelbasiert und
/// nachvollziehbar: jede Ursache stammt aus einer Regel unten, nicht aus einem Modell.
module neko.database.domain.services.diagnosis;

import neko.database.domain.services.inspection : normalizeStatement;
import neko.database.domain.types.monitoring;
import std.algorithm : canFind, filter, map, sort;
import std.array : array, join;
import std.conv : to;
import std.format : format;
import std.string : indexOf, toLower;

@safe:

private struct Rule {
    string[] needles; // irgendeines davon in der Fehlermeldung (klein geschrieben)
    string cause, resolution;
}

private immutable Rule[] rules = [
    Rule(["requires permission", "access denied", "no access"],
        "Missing privileges: the user's role or table grants do not cover the statement.",
        "Grant the needed permission on the table or assign a role that has it (Users and Roles, or POST /api/v1/users/{name}/grants)."),
    Rule(["authentication required", "token", "expired"],
        "Sessions expire or tokens are invalid.",
        "Sign in again; for applications use a service binding and renew the token before it expires."),
    Rule(["unknown table", "table not found", "no such table", "existiert nicht", "unbekannte tabelle"],
        "Statements reference tables that do not exist in this instance (schema drift or a wrong tenant).",
        "Check the tenant the application binds to and deploy the missing tables, or install the data product that provides them."),
    Rule(["unknown column", "unbekannte spalte"],
        "Statements reference columns that do not exist; the client and the table definition are out of sync.",
        "Compare the statement with the table definition (Statistics, $metadata) and migrate the table or the client."),
    Rule(["syntax", "nicht unterstützt", "not supported"],
        "Clients send SQL this database does not understand.",
        "Use the supported dialect (see Help / SQL reference) or switch the client to the REST or OData API."),
    Rule(["transaction", "transaktion", "locked", "gesperrt"],
        "A long-running or abandoned transaction holds the tenant lock.",
        "Commit or roll back open transactions promptly; idle transactions are rolled back after 30 seconds."),
    Rule(["memory limit"],
        "Statements exceed the memory limit of their workload class.",
        "Add filters or LIMIT to the statements, or raise the statement memory limit of the workload class."),
    Rule(["concurrency limit", "statement limit"],
        "More statements run in parallel than the workload class admits.",
        "Raise the total statement limit of the workload class or spread the load over time (see ECN Advisor)."),
    Rule(["timeout"],
        "Statements run longer than the timeout of their workload class.",
        "Run the Index and Partition advisors for the affected tables and merge large deltas."),
    Rule(["read-only replica"],
        "Applications write to a read-only replica.",
        "Point writing applications at the primary, or stop the replication if this tenant should accept writes."),
    Rule(["duplicate", "already exists", "gibt es schon", "existiert bereits"],
        "Objects are created twice (repeated deployment or a retry without a check).",
        "Make deployments idempotent: check for the object first or use CREATE OR REPLACE where available."),
];

private immutable Rule fallback = Rule(null, "Statements fail for different reasons.",
    "Open the trace, check the most frequent statement and its error message.");

/// Fasst die Einträge zusammen. `entries` darf beliebig sortiert sein.
IssueSummary summarize(TraceEntry[] entries, string now) {
    IssueSummary s;
    s.generatedAt = now;
    IssueGroup[string] groups;
    string[] order;
    foreach (e; entries) {
        if (e.kind == "expensive")
            s.expensive++;
        if (e.kind != "error" && e.kind != "violation")
            continue;
        if (e.kind == "error")
            s.errors++;
        else
            s.violations++;
        if (s.from.length == 0 || e.time < s.from)
            s.from = e.time;
        if (e.time > s.until)
            s.until = e.time;
        auto key = normalizeMessage(e.error) ~ " | " ~ e.verb;
        auto g = key in groups;
        if (g is null) {
            auto rule = ruleFor(e.error);
            groups[key] = IssueGroup(normalizeMessage(e.error), 0, e.time, e.time, normalizeStatement(e.statement), null,
                rule.cause, rule.resolution);
            order ~= key;
            g = key in groups;
        }
        g.count++;
        if (e.time < g.firstSeen)
            g.firstSeen = e.time;
        if (e.time > g.lastSeen)
            g.lastSeen = e.time;
        if (e.user.length && !g.users.canFind(e.user))
            g.users ~= e.user;
    }
    s.groups = order.map!(k => groups[k]).array;
    s.groups.sort!((a, b) => a.count > b.count);
    if (s.groups.length) {
        s.rootCause = s.groups[0].cause;
        s.resolution = s.groups[0].resolution;
    }
    s.text = render(s);
    return s;
}

private immutable(Rule) ruleFor(string message) {
    auto m = message.toLower;
    foreach (r; rules)
        foreach (n; r.needles)
            if (m.canFind(n))
                return r;
    return fallback;
}

/// Fehlermeldung ohne Namen und Zahlen in Anführungszeichen, damit gleiche Fehler zusammenfallen.
string normalizeMessage(string message) {
    auto r = normalizeStatement(message);
    return r.length > 160 ? r[0 .. 160] ~ "…" : r;
}

private string render(ref const IssueSummary s) {
    if (s.errors + s.violations == 0)
        return s.expensive
            ? format("No errors were recorded. %s expensive statements were traced; the advisors can tell whether "
                ~ "indexes, partitions or a delta merge would help.", s.expensive)
            : "No errors, limit violations or expensive statements were recorded. The instance looks healthy.";
    string[] lines;
    lines ~= format("Between %s and %s the trace recorded %s failed statements and %s workload limit violations in "
            ~ "%s distinct patterns%s.", s.from, s.until, s.errors, s.violations, s.groups.length,
            s.expensive ? format(", plus %s expensive statements", s.expensive) : "");
    auto top = s.groups[0];
    lines ~= format("The most frequent issue (%s occurrences%s) is: \"%s\".", top.count,
        top.users.length ? ", users " ~ top.users.join(", ") : "", top.pattern);
    lines ~= "Suspected root cause: " ~ top.cause;
    lines ~= "Suggested resolution: " ~ top.resolution;
    if (s.groups.length > 1) {
        string[] others;
        foreach (g; s.groups[1 .. $].length > 3 ? s.groups[1 .. 4] : s.groups[1 .. $])
            others ~= format("\"%s\" (%s×)", g.pattern, g.count);
        lines ~= "Other issues: " ~ others.join("; ") ~ ".";
    }
    return lines.join("\n");
}

unittest {
    TraceEntry e(string time, string user, string error, string kind = "error") {
        TraceEntry t;
        t.time = time;
        t.user = user;
        t.kind = kind;
        t.error = error;
        t.verb = "SELECT";
        t.statement = "SELECT * FROM orders WHERE id = 7";
        return t;
    }

    auto s = summarize([e("2026-11-18T10:00:00Z", "anna", "Requires permission select on table orders"),
            e("2026-11-18T10:05:00Z", "bob", "Requires permission select on table orders"),
            e("2026-11-18T09:00:00Z", "anna", "Syntax: SELECT ..."),
            e("2026-11-18T09:30:00Z", "etl", "Workload class ETL: statement memory limit of 1 MB exceeded", "violation")],
        "2026-11-18T11:00:00Z");
    assert(s.errors == 3 && s.violations == 1 && s.groups.length == 3);
    assert(s.groups[0].count == 2 && s.groups[0].users == ["anna", "bob"]);
    assert(s.rootCause.canFind("privileges") && s.from == "2026-11-18T09:00:00Z");
    assert(s.text.canFind("Suspected root cause") && s.text.canFind("memory limit"));
    assert(summarize(null, "x").text.canFind("healthy"));
}
