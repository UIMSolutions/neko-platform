/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Calculation Views: wiederverwendbare Auswertungslogik über Tabellen, mit Merkmalen (Attribute), Kennzahlen
/// (Measures), Joins und einem festen Filter. Eine View ist eine Definition; ausgeführt wird sie als SELECT mit
/// den Rechten des Aufrufers, sie umgeht also keine Tabellenfreigabe.
module neko.database.domain.entities.calcview;

import neko.database.domain.entities.workload : validObjectName;
import neko.database.domain.enumerations.cloud;
import std.algorithm : all, any, canFind, map;
import std.array : array, join;
import std.ascii : isAlphaNum;
import std.conv : to;
import std.exception : enforce;
import std.string : indexOf, lastIndexOf, strip, toLower, toUpper;

@safe:

struct CalcJoin {
    string table;
    string alias_;
    bool left; // LEFT OUTER statt INNER
    string leftColumn, rightColumn; // jeweils spalte oder tabelle.spalte
}

/// Merkmal: eine Spalte, nach der gruppiert wird.
struct CalcAttribute {
    string column;
    string label; // Name in der Ausgabe; leer: Spaltenname
    string description;
}

/// Kennzahl: eine aggregierte Spalte.
struct CalcMeasure {
    string column;
    Aggregation aggregation = Aggregation.sum;
    string label;
    string description;
}

struct CalculationView {
    string name;
    string label, description;
    CalcViewType viewType = CalcViewType.cube;
    string baseTable;
    string baseAlias;
    CalcJoin[] joins;
    CalcAttribute[] attributes;
    CalcMeasure[] measures;
    string filter; // feste WHERE-Bedingung
    string createdAt, createdBy, updatedAt;
}

/// Name einer Spalte in der Ausgabe.
string outputName(const CalcAttribute a) {
    return a.label.length ? a.label : lastSegment(a.column);
}

string outputName(const CalcMeasure m) {
    return m.label.length ? m.label : enumName(m.aggregation) ~ "_" ~ lastSegment(m.column);
}

/// Namen aller Ausgabespalten in Reihenfolge: erst Merkmale, dann Kennzahlen.
string[] outputColumns(const CalculationView v) {
    string[] r;
    foreach (ref a; v.attributes)
        r ~= outputName(a);
    foreach (ref m; v.measures)
        r ~= outputName(m);
    return r;
}

/// Prüft die Definition vollständig, bevor sie gespeichert wird.
void validate(const CalculationView v) {
    validObjectName(v.name, "View name");
    validIdentifier(v.baseTable, "Base table");
    if (v.baseAlias.length)
        validIdentifier(v.baseAlias, "Alias");
    foreach (j; v.joins) {
        validIdentifier(j.table, "Join table");
        if (j.alias_.length)
            validIdentifier(j.alias_, "Alias");
        validColumnRef(j.leftColumn);
        validColumnRef(j.rightColumn);
    }
    enforce(v.attributes.length + v.measures.length > 0, "A view needs at least one attribute or measure");
    enforce(v.viewType == CalcViewType.cube || v.measures.length == 0, "A dimension view has no measures");
    foreach (a; v.attributes)
        validColumnRef(a.column);
    foreach (m; v.measures)
        validColumnRef(m.column);
    auto names = outputColumns(v);
    foreach (i, n; names) {
        validObjectName(n, "Output column");
        enforce(!names[0 .. i].map!(x => x.toLower).canFind(n.toLower), "Duplicate output column: " ~ n);
    }
    validCondition(v.filter);
    enforce(v.label.length <= 128 && v.description.length <= 1024, "Label or description too long");
}

/// Abfrage auf die View.
struct CalcQuery {
    string filter; // zusätzliche WHERE-Bedingung, mit AND verknüpft
    string orderBy; // Ausgabespalte, optional mit " desc"
    size_t top; // 0: keine Grenze
    size_t skip;
}

/// Erzeugt die SELECT-Anweisung. Sortiert wird nach Position, weil Aggregate keinen Namen haben.
string toSql(const CalculationView v, CalcQuery q = CalcQuery.init) {
    validCondition(q.filter);
    string[] items;
    foreach (ref a; v.attributes)
        items ~= a.column;
    foreach (ref m; v.measures)
        items ~= aggregateSql(m);
    auto distinct = v.viewType == CalcViewType.dimension && v.measures.length == 0;
    auto sql = "SELECT " ~ (distinct ? "DISTINCT " : "") ~ items.join(", ") ~ " FROM " ~ v.baseTable
        ~ (v.baseAlias.length ? " " ~ v.baseAlias : "");
    foreach (j; v.joins)
        sql ~= (j.left ? " LEFT JOIN " : " JOIN ") ~ j.table ~ (j.alias_.length ? " " ~ j.alias_ : "")
            ~ " ON " ~ j.leftColumn ~ " = " ~ j.rightColumn;
    string[] conditions;
    if (v.filter.strip.length)
        conditions ~= "(" ~ v.filter.strip ~ ")";
    if (q.filter.strip.length)
        conditions ~= "(" ~ q.filter.strip ~ ")";
    if (conditions.length)
        sql ~= " WHERE " ~ conditions.join(" AND ");
    if (!distinct && v.measures.length && v.attributes.length)
        sql ~= " GROUP BY " ~ v.attributes.map!(a => a.column).join(", ");
    if (q.orderBy.strip.length) {
        auto spec = q.orderBy.strip;
        bool desc;
        auto space = spec.lastIndexOf(' ');
        if (space > 0) {
            auto dir = spec[space + 1 .. $].toLower;
            enforce(dir == "asc" || dir == "desc", "Order direction must be asc or desc");
            desc = dir == "desc";
            spec = spec[0 .. space].strip;
        }
        auto cols = outputColumns(v);
        size_t pos;
        foreach (i, c; cols)
            if (c.toLower == spec.toLower)
                pos = i + 1;
        enforce(pos > 0, "Unknown output column: " ~ spec);
        sql ~= " ORDER BY " ~ pos.to!string ~ (desc ? " DESC" : "");
    }
    if (q.top)
        sql ~= " LIMIT " ~ q.top.to!string ~ (q.skip ? " OFFSET " ~ q.skip.to!string : "");
    else if (q.skip)
        sql ~= " LIMIT 1000000000 OFFSET " ~ q.skip.to!string;
    return sql;
}

string aggregateSql(const CalcMeasure m) {
    final switch (m.aggregation) {
    case Aggregation.sum:
        return "SUM(" ~ m.column ~ ")";
    case Aggregation.count:
        return "COUNT(" ~ m.column ~ ")";
    case Aggregation.avg:
        return "AVG(" ~ m.column ~ ")";
    case Aggregation.min:
        return "MIN(" ~ m.column ~ ")";
    case Aggregation.max:
        return "MAX(" ~ m.column ~ ")";
    case Aggregation.countDistinct:
        return "COUNT(DISTINCT " ~ m.column ~ ")";
    }
}

/// Tabellen, die eine View liest (für Rechte und Abhängigkeiten).
string[] tablesOf(const CalculationView v) {
    string[] r = [v.baseTable];
    foreach (j; v.joins)
        r ~= j.table;
    return r;
}

private string lastSegment(string column) {
    auto dot = column.lastIndexOf('.');
    return dot >= 0 ? column[dot + 1 .. $] : column;
}

private void validIdentifier(string s, string what) {
    enforce(s.length >= 1 && s.length <= 128 && s.all!(c => isAlphaNum(c) || c == '_'), what ~ " is not a valid name: " ~ s);
}

private void validColumnRef(string s) {
    auto dot = s.indexOf('.');
    if (dot >= 0) {
        validIdentifier(s[0 .. dot], "Column");
        validIdentifier(s[dot + 1 .. $], "Column");
    } else
        validIdentifier(s, "Column");
}

/// Eine Bedingung darf keine zweite Anweisung einschleusen. Die Rechte prüft ohnehin die Ausführung.
private void validCondition(string s) {
    enforce(!s.canFind(';') && !s.canFind("--") && !s.canFind("/*"), "Conditions must not contain ';' or comments");
    enforce(s.length <= 2048, "Condition too long");
}

unittest {
    import std.exception : assertThrown;

    CalculationView v;
    v.name = "SALES_BY_REGION";
    v.baseTable = "orders";
    v.baseAlias = "o";
    v.joins = [CalcJoin("customers", "c", false, "o.customer", "c.id")];
    v.attributes = [CalcAttribute("c.region", "REGION")];
    v.measures = [CalcMeasure("o.amount", Aggregation.sum, "REVENUE"), CalcMeasure("o.id", Aggregation.countDistinct)];
    v.filter = "o.status = 'paid'";
    validate(v);
    assert(outputColumns(v) == ["REGION", "REVENUE", "countDistinct_id"]);
    assert(toSql(v, CalcQuery("", "revenue desc", 10)) ==
            "SELECT c.region, SUM(o.amount), COUNT(DISTINCT o.id) FROM orders o JOIN customers c ON o.customer = c.id"
            ~ " WHERE (o.status = 'paid') GROUP BY c.region ORDER BY 2 DESC LIMIT 10");
    assertThrown(toSql(v, CalcQuery("1=1; DROP TABLE orders")));
    v.viewType = CalcViewType.dimension;
    assertThrown(validate(v));
    v.measures = null;
    assert(toSql(v) == "SELECT DISTINCT c.region FROM orders o JOIN customers c ON o.customer = c.id WHERE (o.status = 'paid')");
}
