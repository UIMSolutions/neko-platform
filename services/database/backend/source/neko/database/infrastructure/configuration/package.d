/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Typsichere Konfiguration des Servers.
///
/// Reihenfolge (spätere Quellen gewinnen):
///   1. Vorgaben im Code (`DatabaseConfig.init`)
///   2. `config/default.json` (oder die Datei aus `HDB_CONFIG`)
///   3. Umgebungsvariablen (`PORT`, `HDB_MODE`, `TENANTS_DIR`, …)
///   4. `VCAP_SERVICES`: Zugangsdaten des benutzerdefinierten Dienstes mit Name oder Tag `hdb-config`
///
/// Die Schlüssel in JSON und VCAP_SERVICES sind die Namen der Umgebungsvariablen in camelCase
/// (z. B. `tenantsDir`, `backupTickSeconds`).
module neko.database.infrastructure.configuration;

import std.algorithm : canFind, map;
import std.array : array, split;
import std.conv : to;
import std.file : exists, readText;
import std.process : environment;
import std.string : strip, toUpper;
import std.uni : isUpper, toLower;
import vibe.data.json : Json, parseJsonString;

@safe:

/// Alle Einstellungen des Servers an einer Stelle.
struct DatabaseConfig {
    // HTTP
    string host = "0.0.0.0";
    ushort port = 8080;
    ulong maxRequestMb = 256;
    string mode; // multi, single, gateway (leer: multi)
    string trustedProxies;
    string frontendDir = "../frontend";
    string publicDir = "public";
    string unixSocket;

    // Ablagen
    string tenantsDir = "data/tenants";
    string tenantsFile = "data/hdb-tenants.json";
    string usersFile = "data/hdb-users.json";
    string rolesFile = "data/hdb-roles.json";
    string logDir = "data/logs";
    string logSettingsFile = "data/hdb-logs.json";
    string cloudFile = "data/hdb-cloud.json";
    string gatewayConfig = "data/hdb-gateway.json";
    // Altbestand vor den Mandanten
    string tablesDir = "data/tables";
    string dataFile = "data/hdb.log";
    string backupDir = "data/backups";

    // Erste Anmeldung
    string adminUser = "admin";
    string adminPassword;
    string systemAdminUser = "sysadmin";
    string systemAdminPassword;

    // Hintergrundaufgaben
    long backupTickSeconds = 60;
    long monitorTickSeconds = 60;
    long replicationRetain = 10_000;
    string replicationAllowedHosts;
    long gatewayConnectSeconds = 5;
    long gatewayReadSeconds = 300;

    // Cloud-Funktionen (HANA-Cloud-ähnlich)
    string region = "eu10";
    string landscape = "local";
    long maxBackupRetentionDays = 215; // 7 Monate

    string[] trustedProxyList() const {
        return trustedProxies.split(",").map!(s => s.strip).array;
    }

    string[] replicationHostList() const {
        return replicationAllowedHosts.split(",").map!(s => s.strip).array;
    }
}

/// Lädt die Konfiguration aus allen Quellen. `env` und `file` lassen sich für Tests ersetzen.
DatabaseConfig loadConfig(string delegate(string) @safe env = null, string file = "") {
    if (env is null)
        env = (string k) @safe => environment.get(k, null);
    DatabaseConfig c;
    auto path = file.length ? file : (env("HDB_CONFIG").length ? env("HDB_CONFIG") : "config/default.json");
    if (exists(path))
        apply(c, parseJsonString(readText(path)));
    foreach (i, ref field; c.tupleof) {
        enum key = __traits(identifier, DatabaseConfig.tupleof[i]);
        auto value = env(envName(key));
        if (value !is null && value.length)
            assign(field, value);
    }
    auto vcap = env("VCAP_SERVICES");
    if (vcap !is null && vcap.length)
        apply(c, vcapCredentials(parseJsonString(vcap), "hdb-config"));
    return c;
}

/// `backupTickSeconds` → `BACKUP_TICK_SECONDS`
string envName(string key) pure {
    string r;
    foreach (ch; key) {
        if (isUpper(ch) && r.length)
            r ~= '_';
        r ~= ch;
    }
    return r.toUpper;
}

/// Zugangsdaten des Dienstes mit Name, Instanzname oder Tag `name` aus VCAP_SERVICES.
Json vcapCredentials(Json vcap, string name) {
    if (vcap.type != Json.Type.object)
        return Json.emptyObject;
    foreach (label, services; vcap.get!(Json[string])) {
        if (services.type != Json.Type.array)
            continue;
        foreach (svc; services.get!(Json[])) {
            bool hit = label == name || svc["name"].opt!string == name || svc["instance_name"].opt!string == name;
            if (!hit && svc["tags"].type == Json.Type.array)
                foreach (t; svc["tags"].get!(Json[]))
                    if (t.opt!string == name)
                        hit = true;
            if (hit && svc["credentials"].type == Json.Type.object)
                return svc["credentials"];
        }
    }
    return Json.emptyObject;
}

private void apply(ref DatabaseConfig c, Json j) {
    if (j.type != Json.Type.object)
        return;
    foreach (i, ref field; c.tupleof) {
        enum key = __traits(identifier, DatabaseConfig.tupleof[i]);
        auto v = j[key];
        if (v.type == Json.Type.undefined || v.type == Json.Type.null_)
            continue;
        assign(field, v.type == Json.Type.string ? v.get!string : v.toString);
    }
}

private void assign(T)(ref T field, string value) {
    static if (is(T == string))
        field = value;
    else static if (is(T == string[]))
        field = value.split(",").map!(s => s.strip).array;
    else static if (is(T == bool))
        field = ["1", "true", "yes", "on"].canFind(value.strip.toLower);
    else
        field = value.strip.to!T;
}

unittest {
    assert(envName("backupTickSeconds") == "BACKUP_TICK_SECONDS");
    assert(envName("port") == "PORT");
    string[string] e = [
        "PORT": "9090", "TENANTS_DIR": "/var/hdb",
        "VCAP_SERVICES": `{"user-provided":[{"name":"hdb-config","credentials":{"region":"us10","maxBackupRetentionDays":100}}]}`
    ];
    auto c = loadConfig((string k) @safe => k in e ? e[k] : null, "does-not-exist.json");
    assert(c.port == 9090 && c.tenantsDir == "/var/hdb");
    assert(c.region == "us10" && c.maxBackupRetentionDays == 100);
    assert(c.usersFile == "data/hdb-users.json");
}
