/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Datenprodukte aus einem Business-Data-Fabric-Katalog: freigegebene, versionierte Datensätze, die ein Mandant
/// als eigene Tabellen installiert und dann mit SQL, OData und Calculation Views abfragt.
module neko.database.domain.entities.dataproduct;

import neko.database.domain.entities.workload : validObjectName;
import std.algorithm : all, map;
import std.array : array, join;
import std.ascii : isAlphaNum;
import std.exception : enforce;
import std.string : replace, toLower;

@safe:

struct DataProductColumn {
    string name;
    string type; // SQL-Typ, etwa INTEGER, TEXT, DECIMAL, DATE
}

struct DataProductTable {
    string name;
    DataProductColumn[] columns;
    string[][] rows; // SQL-Literale je Spalte, etwa 1, 'Berlin', NULL
}

struct DataProduct {
    string id; // etwa bdc.sales.orders
    string title, description, provider, version_;
    string[] tags;
    DataProductTable[] tables;
}

/// Installation eines Datenprodukts in einem Mandanten.
struct InstalledProduct {
    string productId, version_;
    string prefix; // Präfix der Tabellen
    string[] tables;
    string installedAt, installedBy;
}

/// Präfix der Tabellen eines Produkts: aus der Id, Punkte werden zu '_' (bdc.sales.orders → bdc_sales_orders).
string tablePrefix(string productId) {
    return productId.replace(".", "_").replace("-", "_").toLower;
}

/// Name einer installierten Tabelle.
string installedTable(string prefix, string table) {
    return prefix ~ "__" ~ table.toLower;
}

void validate(const DataProduct p) {
    enforce(p.id.length >= 3 && p.id.length <= 96 && p.id.all!(c => isAlphaNum(c) || c == '.' || c == '_' || c == '-'),
        "Invalid data product id: " ~ p.id);
    enforce(p.tables.length > 0, "A data product needs at least one table");
    foreach (t; p.tables) {
        validObjectName(t.name, "Table name");
        enforce(t.columns.length > 0, "Table " ~ t.name ~ " has no columns");
        foreach (c; t.columns) {
            validObjectName(c.name, "Column name");
            enforce(c.type.all!(ch => isAlphaNum(ch) || ch == '(' || ch == ')' || ch == ',' || ch == ' '),
                "Invalid column type: " ~ c.type);
        }
        foreach (r; t.rows) {
            enforce(r.length == t.columns.length, "Row length does not match the columns of " ~ t.name);
            foreach (v; r)
                enforce(!containsTerminator(v), "Invalid literal in table " ~ t.name ~ " of data product " ~ p.id);
        }
    }
}

/// Anweisungen, die ein Produkt installieren.
string[] installStatements(const DataProduct p, string prefix) {
    string[] s;
    foreach (t; p.tables) {
        auto name = installedTable(prefix, t.name);
        s ~= "CREATE TABLE " ~ name ~ " (" ~ t.columns.map!(c => c.name ~ " " ~ c.type).join(", ") ~ ")";
        foreach (r; t.rows) {
            foreach (v; r)
                enforce(!containsTerminator(v), "Invalid literal in data product " ~ p.id);
            s ~= "INSERT INTO " ~ name ~ " VALUES (" ~ r.join(", ") ~ ")";
        }
    }
    return s;
}

private bool containsTerminator(string literal) {
    bool quoted;
    foreach (ch; literal) {
        if (ch == '\'')
            quoted = !quoted;
        else if (ch == ';' && !quoted)
            return true;
    }
    return false;
}

unittest {
    import std.exception : assertThrown;

    auto p = DataProduct("bdc.sales.orders", "Orders", "", "Sales", "1.0.0", null,
        [DataProductTable("orders", [DataProductColumn("id", "INTEGER"), DataProductColumn("city", "TEXT")],
            [["1", "'Berlin'"], ["2", "'a;b'"]])]);
    validate(p);
    auto s = installStatements(p, tablePrefix(p.id));
    assert(s[0] == "CREATE TABLE bdc_sales_orders__orders (id INTEGER, city TEXT)");
    assert(s[2] == "INSERT INTO bdc_sales_orders__orders VALUES (2, 'a;b')");
    p.tables[0].rows ~= ["3", "1); DROP TABLE x"];
    assertThrown(validate(p));
}
