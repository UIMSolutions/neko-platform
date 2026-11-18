/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Werte der Überwachung: Traces von Anweisungen, Messpunkte, Empfehlungen und Zusammenfassungen von Problemen.
module neko.database.domain.types.monitoring;

import neko.database.domain.enumerations.cloud;

@safe:

/// Was der SQL-Trace eines Mandanten aufzeichnet.
struct TraceSettings {
    bool sqlTrace; // alle Anweisungen
    bool traceErrors = true; // fehlgeschlagene Anweisungen
    size_t expensiveThresholdMs = 1000; // teure Anweisungen ab dieser Dauer; 0: aus
    size_t maxEntries = 2000;
}

/// Ein Eintrag im Trace.
struct TraceEntry {
    ulong id;
    string time; // ISO, UTC
    string user;
    string kind; // sql, expensive, error, violation
    string statement; // gekürzt
    string verb; // SELECT, INSERT, ...
    string[] tables;
    double durationMs = 0;
    size_t rows;
    long affected;
    string error;
    string workloadClass;
}

/// Messpunkt eines Mandanten (bzw. der ganzen Instanz) in einem Intervall.
struct MetricSample {
    string time;
    size_t statements, errors, expensive;
    double avgMs = 0, maxMs = 0;
    size_t tables, rows;
    ulong memoryBytes; // geschätzte Größe der Spalten
    double cpuPercent = 0; // des Serverprozesses
    ulong residentBytes; // des Serverprozesses
    size_t reads, writes;
}

/// Zugriffe auf eine Tabelle seit dem Start.
struct TableAccess {
    string table;
    size_t reads, writes;
    size_t filters; // Anweisungen mit WHERE auf der Tabelle
    string[] filterColumns; // in WHERE verwendete Spalten (eindeutig)
    string lastAccess;
}

/// Empfehlung eines Advisors.
struct Recommendation {
    string id;
    AdvisorKind advisor;
    Severity severity = Severity.info;
    string target; // Tabelle, Spalte oder Instanz
    string title;
    string detail;
    string action; // ausführbare Anweisung oder Handlungsanweisung
    bool executable; // action ist eine SQL-Anweisung
    double benefit = 0; // geschätzter Nutzen 0..1 für die Sortierung
    string createdAt;
}

/// Gruppe gleichartiger Fehler.
struct IssueGroup {
    string pattern;
    size_t count;
    string firstSeen, lastSeen;
    string example;
    string[] users;
    string cause, resolution;
}

/// Lesbare Zusammenfassung aus dem Trace.
struct IssueSummary {
    string generatedAt, from, until;
    size_t errors, expensive, violations;
    IssueGroup[] groups;
    string rootCause, resolution;
    string text;
}
