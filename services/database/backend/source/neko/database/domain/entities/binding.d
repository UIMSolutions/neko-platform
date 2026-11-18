/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Bindung einer Anwendung an eine Instanz: ein technischer Benutzer im Mandanten und Zugangsdaten im Format
/// von VCAP_SERVICES. Das Passwort wird nur beim Anlegen ausgegeben und nie gespeichert.
module neko.database.domain.entities.binding;

import neko.database.domain.entities.workload : validObjectName;
import std.exception : enforce;
import std.string : toLower;

@safe:

struct ServiceBinding {
    string name; // eindeutig im Mandanten
    string application;
    string tenant;
    string user; // technischer Benutzer
    string role;
    string createdAt, createdBy;
}

/// Zugangsdaten, wie sie eine gebundene Anwendung in VCAP_SERVICES erhält.
struct BindingCredentials {
    string host;
    ushort port;
    string url; // Basis-URL
    string restUrl, odataUrl, sqlUrl;
    string tenant, schema;
    string user, password;
    string jdbcUrl, odbcConnectionString;
    string[] drivers;
}

/// Name des technischen Benutzers einer Bindung.
string bindingUser(string bindingName) {
    return ("app_" ~ bindingName).toLower;
}

void validate(const ServiceBinding b) {
    validObjectName(b.name, "Binding name");
    enforce(b.application.length >= 1 && b.application.length <= 128, "Application name must have 1 to 128 characters");
}

/// Zugangsdaten zu einer Basis-URL wie http://host:8080.
BindingCredentials credentialsFor(string baseUrl, string tenant, string user, string password) {
    import std.algorithm : findSplit, startsWith;
    import std.conv : to;

    BindingCredentials c;
    c.url = baseUrl;
    auto rest = baseUrl.startsWith("https://") ? baseUrl[8 .. $] : baseUrl.startsWith("http://") ? baseUrl[7 .. $] : baseUrl;
    if (auto slash = rest.findSplit("/"))
        rest = slash[0];
    if (auto p = rest.findSplit(":")) {
        c.host = p[0];
        try
            c.port = p[2].to!ushort;
        catch (Exception)
            c.port = 0;
    } else {
        c.host = rest;
        c.port = baseUrl.startsWith("https://") ? 443 : 80;
    }
    c.restUrl = baseUrl ~ "/api/v1";
    c.odataUrl = baseUrl ~ "/odata/v4";
    c.sqlUrl = baseUrl ~ "/api/v1/sql";
    c.tenant = tenant;
    c.schema = tenant;
    c.user = user;
    c.password = password;
    c.jdbcUrl = "jdbc:hdblite://" ~ c.host ~ ":" ~ c.port.to!string ~ "/?tenant=" ~ tenant;
    c.odbcConnectionString = "DRIVER={HDBLITE};SERVERNODE=" ~ c.host ~ ":" ~ c.port.to!string ~ ";DATABASENAME=" ~ tenant
        ~ ";UID=" ~ user;
    c.drivers = ["REST/JSON (any language)", "OData v4", "Unix socket (hdb-cli)", "D (neko.database.embedded)"];
    return c;
}

unittest {
    auto c = credentialsFor("http://db.local:8080", "acme", "app_shop", "secret");
    assert(c.host == "db.local" && c.port == 8080 && c.odataUrl == "http://db.local:8080/odata/v4");
    assert(credentialsFor("https://db.example", "a", "u", "p").port == 443);
    assert(bindingUser("Shop") == "app_shop");
}
