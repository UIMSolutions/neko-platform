/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Aufzählungen der Cloud-Funktionen (Instanzen, Workload-Klassen, Advisor, Calculation Views).
module neko.database.domain.enumerations.cloud;

import std.conv : to;
import std.string : strip, toLower;
import std.traits : EnumMembers;

@safe:

/// Lebenszyklus einer Datenbankinstanz.
enum InstanceStatus {
    creating,
    running,
    stopped,
    error
}

/// Leistungsklasse: Verhältnis von Arbeitsspeicher zu vCPU.
enum PerformanceClass {
    compute, /// 8 GB je vCPU: rechenintensive Lasten
    memory, /// 16 GB je vCPU: Standard
    highMemory /// 32 GB je vCPU: große Datenmengen
}

/// Welche Analyse eine Empfehlung erzeugt hat.
enum AdvisorKind {
    index, /// Filterspalten und Delta-Anteil
    nse, /// Native Storage Extension: Ladeeinheiten nach Zugriffshäufigkeit
    partition, /// Partitionierung großer Tabellen
    performanceClass, /// Größe und Klasse der Instanz
    ecn /// Elastic Compute Node: Lastspitzen auslagern
}

enum Severity {
    info,
    low,
    medium,
    high
}

/// Ladeeinheit im Sinne der Native Storage Extension.
enum LoadUnit {
    column, /// vollständig im Speicher
    page /// seitenweise bei Bedarf
}

enum CalcViewType {
    cube, /// Kennzahlen und Merkmale, aggregiert
    dimension /// nur Merkmale (Stammdaten)
}

enum Aggregation {
    sum,
    count,
    avg,
    min,
    max,
    countDistinct
}

/// Name in APIs: der Bezeichner des Enum-Werts.
string enumName(E)(E value) if (is(E == enum)) {
    return value.to!string;
}

/// Liest einen Enum-Wert aus seinem Namen, ohne Rücksicht auf Groß- und Kleinschreibung und Bindestriche.
E parseEnum(E)(string name) if (is(E == enum)) {
    auto n = name.strip.toLower;
    string norm(string s) {
        string r;
        foreach (ch; s.toLower)
            if (ch != '-' && ch != '_' && ch != ' ')
                r ~= ch;
        return r;
    }

    foreach (m; [EnumMembers!E])
        if (norm(m.to!string) == norm(n))
            return m;
    throw new Exception("Unknown " ~ E.stringof ~ ": " ~ name);
}

unittest {
    assert(parseEnum!PerformanceClass("high-memory") == PerformanceClass.highMemory);
    assert(parseEnum!Aggregation("COUNT_DISTINCT") == Aggregation.countDistinct);
    assert(enumName(InstanceStatus.running) == "running");
    import std.exception : assertThrown;

    assertThrown(parseEnum!AdvisorKind("magic"));
}
