/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Grobe Einordnung einer SQL-Anweisung für Überwachung und Advisor: Verb, Tabellen, Filterspalten.
/// Kein Parser: was hier nicht erkannt wird, fehlt nur in der Statistik.
module neko.database.domain.services.inspection;

import std.algorithm : canFind, map, uniq, sort;
import std.array : array;
import std.regex : ctRegex, matchAll, matchFirst;
import std.string : indexOf, strip, toLower, toUpper;
import std.uni : icmp;

@safe:

struct StatementShape {
    string verb;
    string[] tables;
    string[] filterColumns;
    bool reads, writes;
}

/// Zerlegt eine Anweisung so weit, wie Überwachung und Advisor es brauchen.
StatementShape inspect(string statement) {
    StatementShape s;
    auto text = maskLiterals(statement.strip);
    auto first = matchFirst(text, ctRegex!(`^\s*(\w+)`));
    s.verb = first.empty ? "" : first[1].toUpper;
    s.reads = ["SELECT", "SHOW", "CALL"].canFind(s.verb);
    s.writes = ["INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER"].canFind(s.verb);
    string[] tables;
    foreach (m; matchAll(text, ctRegex!(`\b(?:FROM|JOIN|INTO|UPDATE|TABLE)\s+(\w+)`, "i")))
        if (!["select", "where", "set", "values", "exists"].canFind(m[1].toLower))
            tables ~= m[1].toLower;
    s.tables = tables.sort.uniq.array;
    auto where = text.toLower.indexOf(" where ");
    if (where >= 0) {
        auto cond = text[where + 7 .. $];
        foreach (stop; [" group by ", " order by ", " limit ", " having "]) {
            auto at = cond.toLower.indexOf(stop);
            if (at >= 0)
                cond = cond[0 .. at];
        }
        string[] cols;
        foreach (m; matchAll(cond, ctRegex!(`([\w.]+)\s*(?:=|<>|!=|<=|>=|<|>|\bLIKE\b|\bIN\b|\bBETWEEN\b|\bIS\b)`, "i"))) {
            auto c = m[1].toLower;
            auto dot = c.indexOf('.');
            if (dot >= 0)
                c = c[dot + 1 .. $];
            if (c.length && !(c[0] >= '0' && c[0] <= '9') && !["and", "or", "not"].canFind(c))
                cols ~= c;
        }
        s.filterColumns = cols.sort.uniq.array;
    }
    return s;
}

/// Ersetzt Zeichenketten durch '?', damit Werte weder in Statistiken landen noch die Erkennung stören.
string maskLiterals(string s) {
    string r;
    bool quoted;
    foreach (ch; s) {
        if (ch == '\'') {
            if (!quoted)
                r ~= "'?'";
            quoted = !quoted;
            continue;
        }
        if (!quoted)
            r ~= ch;
    }
    return r;
}

/// Anweisung ohne Werte: Zahlen und Zeichenketten werden zu '?' (für Fehlergruppen und Traces).
string normalizeStatement(string s) {
    auto masked = maskLiterals(s);
    string r;
    bool inNumber;
    foreach (i, ch; masked) {
        immutable digit = ch >= '0' && ch <= '9';
        immutable boundary = i == 0 || !(masked[i - 1] >= 'a' && masked[i - 1] <= 'z' || masked[i - 1] >= 'A'
                && masked[i - 1] <= 'Z' || masked[i - 1] == '_');
        if (digit && (inNumber || boundary)) {
            if (!inNumber)
                r ~= '?';
            inNumber = true;
            continue;
        }
        inNumber = false;
        r ~= ch;
    }
    return r;
}

unittest {
    auto s = inspect("SELECT o.id, c.name FROM orders o JOIN customers c ON o.c = c.id WHERE o.status = 'x;y' AND c.region IN ('a') ORDER BY 1");
    assert(s.verb == "SELECT" && s.reads && !s.writes);
    assert(s.tables == ["customers", "orders"]);
    assert(s.filterColumns == ["region", "status"]);
    assert(inspect("insert into t values (1)").tables == ["t"]);
    assert(inspect("UPDATE t SET a = 1 WHERE id = 3").filterColumns == ["id"]);
    assert(normalizeStatement("SELECT * FROM t2 WHERE id = 42 AND n = 'abc'") == "SELECT * FROM t2 WHERE id = ? AND n = '?'");
}
