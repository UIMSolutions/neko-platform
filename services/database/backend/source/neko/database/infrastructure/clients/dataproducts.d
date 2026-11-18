/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Katalog der Datenprodukte: drei mitgelieferte Beispielprodukte und alle *.json-Dateien in einem Verzeichnis
/// (DATA_PRODUCTS_DIR), wie sie ein Business-Data-Fabric-Share in die Umgebung legt.
///
/// Format einer Datei:
/// { "id": "bdc.x.y", "title": "…", "provider": "…", "version": "1.0.0", "description": "…", "tags": ["…"],
///   "tables": [ { "name": "t", "columns": [ {"name": "id", "type": "INTEGER"} ], "rows": [ [1, "a"] ] } ] }
module neko.database.infrastructure.clients.dataproducts;

import neko.database.domain;
import neko.database.ports.gateways : IDataProductCatalog;
import std.algorithm : canFind, map, sort;
import std.array : array, replace;
import std.conv : to;
import std.file : SpanMode, dirEntries, exists, isDir, readText;
import std.format : format;
import vibe.core.log : logWarn;
import vibe.data.json : Json, parseJsonString;

@safe:

final class DataProductCatalog : IDataProductCatalog {
    private string directory;

    /// `directory` leer: nur die mitgelieferten Produkte.
    this(string directory = "") {
        this.directory = directory;
    }

    DataProduct[] products() {
        DataProduct[] all = builtinProducts();
        if (directory.length && exists(directory) && isDir(directory))
            foreach (path; listJson(directory)) {
                try {
                    auto p = parseProduct(parseJsonString(readText(path), path));
                    validate(p);
                    if (!all.canFind!(x => x.id == p.id))
                        all ~= p;
                } catch (Exception e)
                    logWarn("Data product %s ignored: %s", path, e.msg);
            }
        all.sort!((a, b) => a.id < b.id);
        return all;
    }

    DataProduct product(string id) {
        foreach (p; products())
            if (p.id == id)
                return p;
        throw new NotFound("No data product " ~ id);
    }

    private static string[] listJson(string dir) @trusted {
        string[] r;
        foreach (e; dirEntries(dir, "*.json", SpanMode.shallow))
            r ~= e.name;
        return r;
    }
}

/// Liest ein Produkt aus JSON; Werte der Zeilen werden zu SQL-Literalen.
DataProduct parseProduct(Json j) {
    DataProduct p;
    p.id = j["id"].get!string;
    p.title = j["title"].opt!string(p.id);
    p.description = j["description"].opt!string;
    p.provider = j["provider"].opt!string;
    p.version_ = j["version"].opt!string("1.0.0");
    if (j["tags"].type == Json.Type.array)
        foreach (t; j["tags"].get!(Json[]))
            p.tags ~= t.get!string;
    foreach (t; j["tables"].get!(Json[])) {
        DataProductTable table;
        table.name = t["name"].get!string;
        foreach (c; t["columns"].get!(Json[]))
            table.columns ~= DataProductColumn(c["name"].get!string, c["type"].opt!string("TEXT"));
        if (t["rows"].type == Json.Type.array)
            foreach (row; t["rows"].get!(Json[])) {
                string[] values;
                foreach (v; row.get!(Json[]))
                    values ~= literal(v);
                table.rows ~= values;
            }
        p.tables ~= table;
    }
    return p;
}

private string literal(Json v) {
    switch (v.type) {
    case Json.Type.null_:
    case Json.Type.undefined:
        return "NULL";
    case Json.Type.string:
        return "'" ~ v.get!string.replace("'", "''") ~ "'";
    case Json.Type.bool_:
        return v.get!bool ? "true" : "false";
    default:
        return v.toString;
    }
}

/// Mitgelieferte Beispielprodukte, damit Installation und Abfrage ohne Share ausprobiert werden können.
DataProduct[] builtinProducts() {
    DataProduct sales;
    sales.id = "bdc.sales.orders";
    sales.title = "Sales Orders";
    sales.provider = "Sales";
    sales.version_ = "1.2.0";
    sales.description = "Customers and their sales orders with amounts and status, for revenue analysis by region and segment.";
    sales.tags = ["sales", "orders", "revenue"];
    auto customers = DataProductTable("customers", [DataProductColumn("id", "INTEGER"),
            DataProductColumn("name", "TEXT"), DataProductColumn("region", "TEXT"), DataProductColumn("segment", "TEXT")]);
    immutable string[4] regions = ["EMEA", "AMER", "APJ", "EMEA"];
    immutable string[3] segments = ["Enterprise", "Midmarket", "SMB"];
    foreach (i; 1 .. 13)
        customers.rows ~= [i.to!string, format("'Customer %02d'", i), "'" ~ regions[i % 4] ~ "'", "'" ~ segments[i % 3] ~ "'"];
    auto orders = DataProductTable("orders", [DataProductColumn("id", "INTEGER"), DataProductColumn("customer", "INTEGER"),
            DataProductColumn("product", "TEXT"), DataProductColumn("quantity", "INTEGER"),
            DataProductColumn("amount", "DECIMAL"), DataProductColumn("status", "TEXT")]);
    immutable string[4] productsList = ["Laptop", "Monitor", "Dock", "Headset"];
    immutable string[3] statuses = ["paid", "open", "paid"];
    foreach (i; 1 .. 61)
        orders.rows ~= [i.to!string, (1 + (i * 7) % 12).to!string, "'" ~ productsList[i % 4] ~ "'", (1 + i % 5).to!string,
            format("%.2f", 49.5 + (i * 37) % 900), "'" ~ statuses[i % 3] ~ "'"];
    sales.tables = [customers, orders];

    DataProduct finance;
    finance.id = "bdc.finance.costcenters";
    finance.title = "Cost Centers";
    finance.provider = "Finance";
    finance.version_ = "2.0.1";
    finance.description = "Cost center master data with planned and actual cost per quarter.";
    finance.tags = ["finance", "controlling"];
    auto centers = DataProductTable("costcenters", [DataProductColumn("id", "TEXT"), DataProductColumn("name", "TEXT"),
            DataProductColumn("department", "TEXT")]);
    immutable string[5] departments = ["IT", "HR", "Sales", "Production", "Logistics"];
    foreach (i, d; departments)
        centers.rows ~= [format("'CC%03d'", (i + 1) * 100), "'" ~ d ~ " cost center'", "'" ~ d ~ "'"];
    auto costs = DataProductTable("costs", [DataProductColumn("costcenter", "TEXT"), DataProductColumn("quarter", "TEXT"),
            DataProductColumn("planned", "DECIMAL"), DataProductColumn("actual", "DECIMAL")]);
    foreach (i; 0 .. departments.length)
        foreach (q; 1 .. 5)
            costs.rows ~= [format("'CC%03d'", (i + 1) * 100), format("'2026-Q%s'", q), format("%s", 100_000 + i * 25_000),
                format("%s", 95_000 + i * 25_000 + q * 3_100)];
    finance.tables = [centers, costs];

    DataProduct hr;
    hr.id = "bdc.hr.workforce";
    hr.title = "Workforce";
    hr.provider = "People";
    hr.version_ = "1.0.0";
    hr.description = "Headcount by country and job family, without personal data.";
    hr.tags = ["hr", "headcount"];
    auto heads = DataProductTable("headcount", [DataProductColumn("country", "TEXT"), DataProductColumn("jobfamily", "TEXT"),
            DataProductColumn("employees", "INTEGER")]);
    immutable string[4] countries = ["DE", "US", "IN", "BR"];
    immutable string[3] families = ["Engineering", "Sales", "Support"];
    foreach (ci, c; countries)
        foreach (fi, f; families)
            heads.rows ~= ["'" ~ c ~ "'", "'" ~ f ~ "'", (20 + ci * 13 + fi * 7).to!string];
    hr.tables = [heads];
    return [sales, finance, hr];
}

unittest {
    import neko.database.application.services.sql : SqlService;
    import neko.database.persistence.repositories.memory : MemoryTableRepository;

    auto catalog = new DataProductCatalog;
    assert(catalog.products().length == 3);
    auto sql = new SqlService(new MemoryTableRepository);
    foreach (p; catalog.products()) {
        validate(p);
        foreach (s; installStatements(p, tablePrefix(p.id)))
            sql.execute(s);
    }
    assert(sql.execute("SELECT COUNT(*) FROM bdc_sales_orders__orders").rows[0][0] == Value(60L));
    auto p = parseProduct(parseJsonString(`{"id":"x.y","tables":[{"name":"t","columns":[{"name":"a","type":"TEXT"}],"rows":[["it's"],[null]]}]}`));
    assert(p.tables[0].rows == [["'it''s'"], ["NULL"]]);
}
