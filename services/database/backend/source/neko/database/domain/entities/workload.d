/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Workload-Management: Klassen mit Grenzen und Zuordnungen von Benutzern und Rollen zu Klassen.
module neko.database.domain.entities.workload;

import std.algorithm : all, canFind;
import std.ascii : isAlphaNum;
import std.exception : enforce;
import std.string : strip, toLower;

@safe:

/// Grenzen für alle Anweisungen einer Klasse. 0 bedeutet: keine Grenze.
struct WorkloadClass {
    string name;
    int priority = 5; // 0 (niedrig) bis 9 (hoch); bestimmt die Reihenfolge, wenn mehrere Klassen passen
    size_t statementTimeoutSeconds; // längere Anweisungen werden als Verstoß protokolliert
    size_t statementMemoryLimitMb; // Ergebnisse darüber werden verworfen
    size_t totalStatementLimit; // gleichzeitige Anweisungen der Klasse
    size_t statementThreadLimit; // Parallelität einer Anweisung (für parallele Auswertungen)
    bool enabled = true;
    string description;
}

/// Ordnet Benutzer oder Rollen einer Klasse zu. Ein Benutzer geht vor einer Rolle.
struct WorkloadMapping {
    string name;
    string workloadClass;
    string userName; // leer: alle Benutzer
    string roleName; // leer: alle Rollen
}

/// Gültiger Name für Klassen, Zuordnungen, Views und Bindungen: 1 bis 64 Zeichen aus Buchstaben, Ziffern und '_'.
string validObjectName(string name, string what = "Name") {
    auto n = name.strip;
    enforce(n.length >= 1 && n.length <= 64 && n.all!(c => isAlphaNum(c) || c == '_'),
        what ~ " uses 1 to 64 letters, digits or '_'");
    return n;
}

void validate(const WorkloadClass c) {
    validObjectName(c.name, "Workload class name");
    enforce(c.priority >= 0 && c.priority <= 9, "Priority must be between 0 and 9");
    enforce(c.statementTimeoutSeconds <= 86_400, "Timeout must be at most one day");
    enforce(c.statementThreadLimit <= 1024, "Thread limit must be at most 1024");
}

void validate(const WorkloadMapping m, const WorkloadClass[] classes) {
    validObjectName(m.name, "Mapping name");
    enforce(m.userName.length || m.roleName.length, "A mapping needs a user or a role");
    bool known;
    foreach (c; classes)
        if (c.name == m.workloadClass)
            known = true;
    enforce(known, "Unknown workload class: " ~ m.workloadClass);
}

/// Klasse für einen Benutzer: zuerst Zuordnungen über den Benutzer, dann über die Rolle; bei mehreren die mit der
/// höchsten Priorität. Gibt den Index in `classes` zurück; ohne Treffer oder bei abgeschalteter Klasse: -1.
ptrdiff_t resolveWorkload(const WorkloadClass[] classes, const WorkloadMapping[] mappings, string user, string role) {
    ptrdiff_t best = -1;
    int bestRank = -1;
    foreach (m; mappings) {
        int rank;
        if (m.userName.length && m.userName.toLower == user.toLower)
            rank = 20;
        else if (m.userName.length == 0 && m.roleName.length && m.roleName.toLower == role.toLower)
            rank = 10;
        else
            continue;
        foreach (i, ref c; classes)
            if (c.name == m.workloadClass && c.enabled && rank + c.priority > bestRank) {
                best = i;
                bestRank = rank + c.priority;
            }
    }
    return best;
}

unittest {
    import std.exception : assertThrown;

    auto classes = [WorkloadClass("REPORTING", 3, 60, 512, 2), WorkloadClass("ETL", 7, 0, 0, 1)];
    auto mappings = [WorkloadMapping("m1", "REPORTING", "", "viewer"), WorkloadMapping("m2", "ETL", "loader")];
    assert(resolveWorkload(classes, mappings, "anna", "viewer") == 0);
    assert(resolveWorkload(classes, mappings, "LOADER", "viewer") == 1);
    assert(resolveWorkload(classes, mappings, "bob", "admin") == -1);
    classes[1].enabled = false;
    assert(resolveWorkload(classes, mappings, "loader", "viewer") == 0);
    assertThrown(validate(WorkloadMapping("x", "NOPE", "a"), classes));
    assertThrown(validObjectName("a b"));
}
