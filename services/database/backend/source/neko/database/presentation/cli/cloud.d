/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// `hdb-cli cloud …`: Verwaltung über die REST-API eines laufenden Servers. Instanzen (Bereich system), Workloads,
/// Überwachung, Advisor, Calculation Views, Bindungen, Datenprodukte, Sicherungs-Aufbewahrung und Assistent.
/// Die Befehlstabelle ist von der Übertragung getrennt (ICloudTransport), damit sie sich ohne Server testen lässt.
module neko.database.presentation.cli.cloud;

import neko.database.presentation.cli.format : formatCsv, formatTable;
import neko.database.presentation.cli.interfaces : ICliOutput;
import std.algorithm : canFind, findSplit, map, startsWith;
import std.array : array, join, replace;
import std.conv : to;
import std.exception : enforce;
import std.file : readText;
import std.string : strip, toLower;
import vibe.data.json : Json, parseJsonString;
import vibe.textfilter.urlencode : urlEncode;

@safe:

/// Eine Anfrage an die REST-API; Fehler kommen als Ausnahme mit der Meldung des Servers.
interface ICloudTransport {
    Json request(string method, string path, Json body_ = Json.undefined);
}

/// Aufruf von `hdb-cli cloud`.
struct CloudCommand {
    string server = "http://localhost:8080";
    string user, tenant;
    string format = "table"; // table, json, csv
    string[] words; // Befehl und Argumente ohne Optionen
    string[string] options; // --name=wert bzw. --name wert; Schalter ohne Wert sind "true"
}

CloudCommand parseCloudArgs(string[] args) {
    CloudCommand c;
    for (size_t i = 0; i < args.length; i++) {
        auto a = args[i];
        if (!a.startsWith("--")) {
            c.words ~= a;
            continue;
        }
        string name = a[2 .. $], value;
        if (auto p = name.findSplit("=")) {
            if (p[1].length) {
                name = p[0];
                value = p[2];
            }
        }
        if (value.length == 0) {
            if (i + 1 < args.length && !args[i + 1].startsWith("--") && !flags.canFind(name))
                value = args[++i];
            else
                value = "true";
        }
        switch (name) {
        case "server":
            c.server = value;
            break;
        case "user":
            c.user = value;
            break;
        case "tenant":
            c.tenant = value;
            break;
        case "json":
            c.format = "json";
            break;
        case "csv":
            c.format = "csv";
            break;
        default:
            c.options[name] = value;
        }
    }
    return c;
}

private immutable string[] flags = ["json", "csv", "nse", "no-nse", "disabled", "sql-trace", "no-sql-trace", "help"];

string cloudUsage(string program) {
    return "Usage: " ~ program ~ ` cloud [--server URL] [--tenant NAME] [--user NAME] [--json|--csv] COMMAND ...
Manages a running server through its REST API. The password comes from HDB_PASSWORD or is asked for;
instead of --user, a session token can be passed in HDB_TOKEN.

System (sign in with --tenant system):
  instances list | show NAME | metrics NAME | advisors NAME
  instances create NAME --memory GB [--storage GB] [--class compute|memory|highMemory] [--nse] [--ecn N]
                        [--description TEXT] [--admin NAME]      (admin password from HDB_ADMIN_PASSWORD)
  instances resize NAME --memory GB [--storage GB] | class NAME CLASS | nse NAME on|off | ecn NAME N
  instances start NAME | stop NAME | delete NAME

Tenant:
  monitor | traces [--kind sql|expensive|error|violation] [--user U] [--text T] [--limit N] | issues | access
  trace-settings [--sql-trace|--no-sql-trace] [--expensive-ms N] [--max-entries N] | clear-traces
  advisors [run [--advisors index,nse,partition,performanceClass,ecn]]
  workloads classes | class NAME [--priority 0-9] [--timeout S] [--memory-limit MB] [--limit N] [--threads N] [--disabled]
  workloads delete-class NAME | mappings | map NAME --class C [--user U] [--role R] | unmap NAME
  views list | show NAME | sql NAME | data NAME [--filter COND] [--orderby COL [desc]] [--top N] [--skip N]
  views create FILE.json | delete NAME
  bindings list | create NAME --application APP [--role ROLE] | delete NAME
  products list | show ID | install ID | uninstall ID
  backups retention DAYS          (0 to 215 days for scheduled and safety backups)
  ask "MESSAGE"                   (assistant; several tasks with ';' or 'then')
`;
}

/// Führt einen Befehl aus und schreibt das Ergebnis. Gibt den Exit-Code zurück.
int runCloudCommand(CloudCommand c, ICloudTransport http, ICliOutput output, string delegate(string) @safe env = null) {
    if (env is null)
        env = (string key) @safe => cast(string) null;
    auto w = c.words;
    enforce(w.length, "No command; see --help");
    string arg(size_t i, string what) {
        enforce(w.length > i, "Missing " ~ what);
        return w[i];
    }

    string opt(string name, string fallback = "") {
        return c.options.get(name, fallback);
    }

    string seg(string s) {
        return urlEncode(s);
    }

    Json result;
    string[] columns; // leer: alle einfachen Felder
    switch (w[0]) {
    case "instances":
        auto verb = w.length > 1 ? w[1] : "list";
        switch (verb) {
        case "list":
            result = http.request("GET", "/api/v1/cloud/instances");
            columns = ["name", "status", "performanceClass", "memoryGb", "vcpus", "storageGb", "nseEnabled", "ecnNodes", "users"];
            break;
        case "show":
            result = http.request("GET", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")));
            break;
        case "create":
            auto b = Json.emptyObject;
            b["name"] = arg(2, "instance name");
            b["memoryGb"] = opt("memory", "32").to!long;
            if (opt("storage").length)
                b["storageGb"] = opt("storage").to!long;
            b["performanceClass"] = opt("class", "memory");
            b["nseEnabled"] = opt("nse") == "true";
            b["ecnNodes"] = opt("ecn", "0").to!long;
            b["description"] = opt("description");
            b["adminName"] = opt("admin", "admin");
            auto pw = env("HDB_ADMIN_PASSWORD");
            enforce(pw !is null && pw.length, "Set HDB_ADMIN_PASSWORD to the password of the instance administrator");
            b["adminPassword"] = pw;
            result = http.request("POST", "/api/v1/cloud/instances", b);
            break;
        case "resize":
            auto b = Json.emptyObject;
            b["memoryGb"] = opt("memory").to!long;
            if (opt("storage").length)
                b["storageGb"] = opt("storage").to!long;
            result = http.request("PATCH", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")), b);
            break;
        case "class":
            result = http.request("PATCH", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")),
                Json(["performanceClass": Json(arg(3, "performance class"))]));
            break;
        case "nse":
            result = http.request("PATCH", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")),
                Json(["nseEnabled": Json(["on", "true", "yes"].canFind(arg(3, "on or off").toLower))]));
            break;
        case "ecn":
            result = http.request("PATCH", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")),
                Json(["ecnNodes": Json(arg(3, "number of nodes").to!long)]));
            break;
        case "start", "stop":
            result = http.request("POST", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")) ~ "/" ~ verb);
            break;
        case "delete":
            http.request("DELETE", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")));
            output.write("Instance " ~ w[2] ~ " deleted.\n");
            return 0;
        case "metrics":
            result = http.request("GET", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")) ~ "/metrics");
            columns = ["time", "statements", "errors", "avgMs", "memoryBytes", "cpuPercent"];
            break;
        case "advisors":
            result = http.request("GET", "/api/v1/cloud/instances/" ~ seg(arg(2, "instance name")) ~ "/advisors");
            columns = ["advisor", "severity", "title", "action"];
            break;
        default:
            throw new Exception("Unknown instances command: " ~ verb);
        }
        break;
    case "monitor":
        auto o = http.request("GET", "/api/v1/monitoring");
        if (c.format == "json") {
            output.write(o.toPrettyString ~ "\n");
            return 0;
        }
        output.write("Tenant " ~ o["tenant"].opt!string ~ ": " ~ o["statements"].to!string ~ " statements, "
                ~ o["errors"].to!string ~ " errors, " ~ o["expensive"].to!string ~ " expensive, "
                ~ o["violations"].to!string ~ " workload violations since start; " ~ o["workers"].to!string
                ~ " cores.\n");
        result = o["samples"];
        columns = ["time", "statements", "errors", "expensive", "avgMs", "maxMs", "tables", "rows", "memoryBytes", "cpuPercent"];
        break;
    case "traces":
        string q = "?limit=" ~ opt("limit", "50");
        foreach (k; ["kind", "user", "text"])
            if (opt(k).length)
                q ~= "&" ~ k ~ "=" ~ urlEncode(opt(k));
        result = http.request("GET", "/api/v1/monitoring/traces" ~ q);
        columns = ["id", "time", "kind", "user", "durationMs", "rows", "statement", "error"];
        break;
    case "issues":
        auto s = http.request("GET", "/api/v1/monitoring/issues");
        if (c.format == "json")
            output.write(s.toPrettyString ~ "\n");
        else
            output.write(s["text"].opt!string ~ "\n");
        return 0;
    case "access":
        result = http.request("GET", "/api/v1/monitoring/access");
        columns = ["table", "reads", "writes", "filters", "filterColumns", "lastAccess"];
        break;
    case "trace-settings":
        auto b = Json.emptyObject;
        if (opt("sql-trace").length)
            b["sqlTrace"] = true;
        if (opt("no-sql-trace").length)
            b["sqlTrace"] = false;
        if (opt("expensive-ms").length)
            b["expensiveThresholdMs"] = opt("expensive-ms").to!long;
        if (opt("max-entries").length)
            b["maxEntries"] = opt("max-entries").to!long;
        result = b.length ? http.request("PUT", "/api/v1/monitoring/trace-settings", b)
            : http.request("GET", "/api/v1/monitoring/trace-settings");
        break;
    case "clear-traces":
        http.request("DELETE", "/api/v1/monitoring/traces");
        output.write("Trace cleared.\n");
        return 0;
    case "advisors":
        if (w.length > 1 && w[1] == "run") {
            auto b = Json.emptyObject;
            if (opt("advisors").length)
                b["advisors"] = Json(opt("advisors").replace(" ", "").to!string.splitList.map!(x => Json(x)).array);
            result = http.request("POST", "/api/v1/advisors/run", b);
        } else
            result = http.request("GET", "/api/v1/advisors");
        columns = ["advisor", "severity", "target", "title", "action"];
        break;
    case "workloads":
        auto verb = w.length > 1 ? w[1] : "classes";
        switch (verb) {
        case "classes":
            result = http.request("GET", "/api/v1/workloads/classes");
            break;
        case "class":
            auto b = Json.emptyObject;
            b["priority"] = opt("priority", "5").to!long;
            b["statementTimeoutSeconds"] = opt("timeout", "0").to!long;
            b["statementMemoryLimitMb"] = opt("memory-limit", "0").to!long;
            b["totalStatementLimit"] = opt("limit", "0").to!long;
            b["statementThreadLimit"] = opt("threads", "0").to!long;
            b["enabled"] = opt("disabled") != "true";
            b["description"] = opt("description");
            result = http.request("PUT", "/api/v1/workloads/classes/" ~ seg(arg(2, "class name")), b);
            break;
        case "delete-class":
            http.request("DELETE", "/api/v1/workloads/classes/" ~ seg(arg(2, "class name")));
            output.write("Workload class " ~ w[2] ~ " deleted.\n");
            return 0;
        case "mappings":
            result = http.request("GET", "/api/v1/workloads/mappings");
            break;
        case "map":
            result = http.request("PUT", "/api/v1/workloads/mappings/" ~ seg(arg(2, "mapping name")),
                Json(["workloadClass": Json(opt("class")), "userName": Json(opt("user")), "roleName": Json(opt("role"))]));
            break;
        case "unmap":
            http.request("DELETE", "/api/v1/workloads/mappings/" ~ seg(arg(2, "mapping name")));
            output.write("Mapping " ~ w[2] ~ " deleted.\n");
            return 0;
        default:
            throw new Exception("Unknown workloads command: " ~ verb);
        }
        break;
    case "views":
        auto verb = w.length > 1 ? w[1] : "list";
        switch (verb) {
        case "list":
            result = http.request("GET", "/api/v1/views");
            columns = ["name", "viewType", "baseTable", "label", "updatedAt"];
            break;
        case "show":
            result = http.request("GET", "/api/v1/views/" ~ seg(arg(2, "view name")));
            break;
        case "sql":
            output.write(http.request("GET", "/api/v1/views/" ~ seg(arg(2, "view name")) ~ "/sql")["sql"].get!string ~ "\n");
            return 0;
        case "data":
            string q = "?top=" ~ opt("top", "100") ~ "&skip=" ~ opt("skip", "0");
            if (opt("filter").length)
                q ~= "&filter=" ~ urlEncode(opt("filter"));
            if (opt("orderby").length)
                q ~= "&orderby=" ~ urlEncode(opt("orderby"));
            auto d = http.request("GET", "/api/v1/views/" ~ seg(arg(2, "view name")) ~ "/data" ~ q);
            result = d["rows"];
            columns = d["columns"].get!(Json[]).map!(x => x.get!string).array;
            break;
        case "create":
            result = http.request("POST", "/api/v1/views", parseJsonString(readFile(arg(2, "definition file"))));
            break;
        case "delete":
            http.request("DELETE", "/api/v1/views/" ~ seg(arg(2, "view name")));
            output.write("View " ~ w[2] ~ " deleted.\n");
            return 0;
        default:
            throw new Exception("Unknown views command: " ~ verb);
        }
        break;
    case "bindings":
        auto verb = w.length > 1 ? w[1] : "list";
        switch (verb) {
        case "list":
            result = http.request("GET", "/api/v1/bindings");
            break;
        case "create":
            auto r = http.request("POST", "/api/v1/bindings", Json(["name": Json(arg(2, "binding name")),
                    "application": Json(opt("application", w[2])), "role": Json(opt("role"))]));
            output.write("Binding created. Store these credentials now, the password is not shown again:\n");
            output.write(r["credentials"].toPrettyString ~ "\n");
            return 0;
        case "delete":
            http.request("DELETE", "/api/v1/bindings/" ~ seg(arg(2, "binding name")));
            output.write("Binding " ~ w[2] ~ " deleted.\n");
            return 0;
        default:
            throw new Exception("Unknown bindings command: " ~ verb);
        }
        break;
    case "products":
        auto verb = w.length > 1 ? w[1] : "list";
        switch (verb) {
        case "list":
            result = http.request("GET", "/api/v1/dataproducts");
            columns = ["id", "version", "title", "provider", "rows", "installed"];
            break;
        case "show":
            result = http.request("GET", "/api/v1/dataproducts/" ~ seg(arg(2, "product id")));
            break;
        case "install":
            result = http.request("POST", "/api/v1/dataproducts/" ~ seg(arg(2, "product id")) ~ "/install");
            break;
        case "uninstall":
            http.request("DELETE", "/api/v1/dataproducts/" ~ seg(arg(2, "product id")) ~ "/install");
            output.write("Data product " ~ w[2] ~ " uninstalled.\n");
            return 0;
        default:
            throw new Exception("Unknown products command: " ~ verb);
        }
        break;
    case "backups":
        enforce(w.length > 2 && w[1] == "retention", "Usage: backups retention DAYS");
        result = http.request("PUT", "/api/v1/backups/retention", Json(["retentionDays": Json(w[2].to!long)]));
        break;
    case "ask":
        enforce(w.length > 1, "Usage: ask \"message\"");
        auto r = http.request("POST", "/api/v1/assistant", Json(["message": Json(w[1 .. $].join(" "))]));
        if (c.format == "json")
            output.write(r.toPrettyString ~ "\n");
        else
            output.write(r["text"].opt!string ~ "\n");
        return 0;
    default:
        throw new Exception("Unknown command: " ~ w[0]);
    }
    output.write(render(result, columns, c.format));
    return 0;
}

/// Ergebnis als Tabelle, CSV oder JSON. Ein einzelnes Objekt wird als Name/Wert-Liste gezeigt.
string render(Json result, string[] columns, string format) {
    if (format == "json")
        return result.toPrettyString ~ "\n";
    if (result.type == Json.Type.object) {
        string[][] rows;
        foreach (k, v; result.get!(Json[string]))
            rows ~= [k, cell(v)];
        import std.algorithm : sort;

        rows.sort!((a, b) => a[0] < b[0]);
        return format == "csv" ? formatCsv(["field", "value"], rows) : formatTable(["field", "value"], rows);
    }
    if (result.type != Json.Type.array)
        return cell(result) ~ "\n";
    auto items = result.get!(Json[]);
    if (items.length == 0)
        return "(none)\n";
    if (columns.length == 0)
        foreach (k, v; items[0].get!(Json[string]))
            if (v.type != Json.Type.object && v.type != Json.Type.array)
                columns ~= k;
    string[][] rows;
    foreach (item; items)
        rows ~= columns.map!(col => cell(item[col])).array;
    return format == "csv" ? formatCsv(columns, rows) : formatTable(columns, rows);
}

private string cell(Json v) {
    switch (v.type) {
    case Json.Type.undefined:
    case Json.Type.null_:
        return "";
    case Json.Type.string:
        auto s = v.get!string;
        return s.length > 80 ? s[0 .. 77] ~ "..." : s;
    case Json.Type.array:
        return v.get!(Json[]).map!(x => cell(x)).join(", ");
    default:
        return v.toString;
    }
}

private string[] splitList(string s) {
    import std.array : split;

    return s.split(",");
}

private string readFile(string path) @trusted {
    return readText(path);
}

unittest {
    final class Fake : ICloudTransport {
        string[] calls;
        Json request(string method, string path, Json body_ = Json.undefined) {
            calls ~= method ~ " " ~ path ~ (body_.type == Json.Type.undefined ? "" : " " ~ body_.toString);
            if (path == "/api/v1/cloud/instances")
                return parseJsonString(`[{"name":"acme","status":"running","performanceClass":"memory","memoryGb":32,`
                        ~ `"vcpus":2,"storageGb":128,"nseEnabled":false,"ecnNodes":0,"users":1}]`);
            return Json.emptyObject;
        }
    }

    final class Out : ICliOutput {
        string text;
        void write(string t) {
            text ~= t;
        }

        void error(string t) {
            text ~= t;
        }
    }

    auto c = parseCloudArgs(["--server", "http://h:1", "--json", "instances", "list"]);
    assert(c.server == "http://h:1" && c.format == "json" && c.words == ["instances", "list"]);
    c = parseCloudArgs(["instances", "list"]);
    auto http = new Fake;
    auto output = new Out;
    assert(runCloudCommand(c, http, output) == 0);
    assert(output.text.canFind("acme") && output.text.canFind("running"));
    runCloudCommand(parseCloudArgs(["workloads", "class", "ETL", "--priority", "7", "--disabled"]), http, output);
    assert(http.calls[$ - 1].canFind("PUT /api/v1/workloads/classes/ETL") && http.calls[$ - 1].canFind(`"enabled":false`));
    runCloudCommand(parseCloudArgs(["instances", "create", "x", "--memory=64", "--nse"]), http, output,
        (string k) @safe => k == "HDB_ADMIN_PASSWORD" ? "correct-horse-12" : null);
    assert(http.calls[$ - 1].canFind(`"memoryGb":64`) && http.calls[$ - 1].canFind(`"nseEnabled":true`));
    runCloudCommand(parseCloudArgs(["ask", "merge", "delta;", "checkpoint"]), http, output);
    assert(http.calls[$ - 1].canFind(`"message":"merge delta; checkpoint"`));
}
