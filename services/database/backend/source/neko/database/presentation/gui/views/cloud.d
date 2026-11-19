/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Seiten des Admin-Clients für die Cloud-Funktionen: Instanzen (Bereich system), Überwachung, Advisor, Workloads,
/// Calculation Views, Bindungen, Datenprodukte und Assistent. Alles läuft über die REST-API mit der Anmeldung des
/// Clients; der Server prüft jede Aktion.
module neko.database.presentation.gui.views.cloud;

import neko.database.presentation.gui.models.api;
import neko.database.presentation.gui.views.pages : Page;
import neko.database.presentation.gui.views.widgets;
import std.algorithm : map;
import std.array : array, join, split;
import std.conv : to;
import std.format : format;
import std.json : JSONType, JSONValue, parseJSON;
import std.string : strip;
import gtk.Box;
import gtk.Button;
import gtk.Entry;
import gtk.Label;
import gtk.Paned;
import gtk.ScrolledWindow;
import gtk.TextView;
import gtk.Widget;
import gtk.Window;
import gtk.c.types : Orientation, PolicyType, WrapMode;

/// Aktion in der Werkzeugleiste einer Listenseite.
struct PageAction {
    string label;
    void delegate(ResourcePage page) run;
}

/// Liste aus einem GET-Endpunkt mit Aktionen.
class ResourcePage : Page {
    private string name, path;
    private string[] keys, headers;
    private Box box;
    protected DataGrid grid;
    protected Label info;

    this(HdbClient client, Window window, void delegate() signedOut, string name, string path, string[] keys,
        string[] headers, PageAction[] actions) {
        super(client, window, signedOut);
        this.name = name;
        this.path = path;
        this.keys = keys;
        this.headers = headers;
        box = pageBox();
        if (actions.length) {
            auto bar = toolbar();
            foreach (a; actions) {
                auto act = a.run;
                bar.packStart(button(a.label, () { act(this); }), false, false, 0);
            }
            box.packStart(bar, false, false, 0);
        }
        info = new Label("");
        info.setXalign(0);
        info.setLineWrap(true);
        info.setSelectable(true);
        box.packStart(info, false, false, 0);
        grid = new DataGrid();
        box.packStart(grid.widget, true, true, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return name;
    }

    override void refresh() {
        run({ grid.show(jsonGrid(load(), keys, headers)); });
    }

    /// Daten der Liste; Unterklassen können sie anders holen.
    protected JSONValue load() {
        return client.request("GET", path);
    }

    /// Wert der Spalte `header` der markierten Zeile; meldet, wenn nichts markiert ist.
    string selection(string header) {
        auto v = grid.selected(header);
        if (v.length == 0)
            showMessage(window, "Select a row first.", false);
        return v;
    }

    /// Führt eine Anfrage aus und lädt danach neu; true bei Erfolg.
    bool act(void delegate() action) {
        if (!run(action))
            return false;
        refresh();
        return true;
    }

    HdbClient api() {
        return client;
    }

    /// Führt eine Anfrage aus und zeigt Fehler an; true bei Erfolg.
    bool attempt(void delegate() action) {
        return run(action);
    }

    Window parent() {
        return window;
    }
}

private JSONValue obj(JSONValue[string] fields) {
    return JSONValue(fields);
}

private long number(string s, long fallback = 0) {
    auto t = s.strip;
    if (t.length == 0)
        return fallback;
    try
        return t.to!long;
    catch (Exception)
        throw new ApiError(400, "Not a number: " ~ t);
}

private string seg(string s) {
    return HdbClient.pathSegment(s);
}

// --- Instanzen (Bereich system) ---

ResourcePage instancesPage(HdbClient client, Window window, void delegate() signedOut) {
    PageAction[] actions;
    if (client.me.can("manageInstances")) {
        actions ~= PageAction("New instance", (p) {
            auto f = new FormDialog(p.parent, "Create instance", "Create");
            f.text("name", "Name").text("description", "Description").text("memory", "Memory (GB, multiple of 16)", "32")
                .text("storage", "Storage (GB, empty: 4 × memory)").choice("class", "Performance class",
                    ["memory", "compute", "highMemory"]).flag("nse", "Native Storage Extension", false)
                .text("ecn", "Elastic compute nodes", "0").text("admin", "Administrator", "admin")
                .text("password", "Administrator password", "", true);
            scope (exit)
                f.close();
            if (!f.run())
                return;
            p.act({
                auto b = obj(["name": JSONValue(f["name"]), "description": JSONValue(f["description"]),
                        "memoryGb": JSONValue(number(f["memory"], 32)), "performanceClass": JSONValue(f["class"]),
                        "nseEnabled": JSONValue(f.checked("nse")), "ecnNodes": JSONValue(number(f["ecn"])),
                        "adminName": JSONValue(f["admin"]), "adminPassword": JSONValue(f["password"])]);
                if (f["storage"].strip.length)
                    b["storageGb"] = number(f["storage"]);
                p.api.request("POST", "/api/v1/cloud/instances", b);
            });
        });
        actions ~= PageAction("Resize", (p) {
            auto name = p.selection("Name");
            if (!name.length)
                return;
            auto f = new FormDialog(p.parent, "Resize " ~ name, "Apply");
            f.text("memory", "Memory (GB)", p.grid.selected("Memory GB")).text("storage", "Storage (GB)",
                p.grid.selected("Storage GB")).choice("class", "Performance class", ["memory", "compute", "highMemory"],
                p.grid.selected("Class")).flag("nse", "Native Storage Extension", p.grid.selected("NSE") == "true")
                .text("ecn", "Elastic compute nodes", p.grid.selected("ECN"));
            scope (exit)
                f.close();
            if (f.run())
                p.act({
                    p.api.request("PATCH", "/api/v1/cloud/instances/" ~ seg(name), obj([
                            "memoryGb": JSONValue(number(f["memory"])), "storageGb": JSONValue(number(f["storage"])),
                            "performanceClass": JSONValue(f["class"]), "nseEnabled": JSONValue(f.checked("nse")),
                            "ecnNodes": JSONValue(number(f["ecn"]))
                        ]));
                });
        });
        foreach (verb; ["start", "stop"]) {
            auto v = verb;
            actions ~= PageAction(v == "start" ? "Start" : "Stop", (p) {
                auto name = p.selection("Name");
                if (name.length)
                    p.act({ p.api.request("POST", "/api/v1/cloud/instances/" ~ seg(name) ~ "/" ~ v); });
            });
        }
        actions ~= PageAction("Delete", (p) {
            auto name = p.selection("Name");
            if (name.length && confirm(p.parent, "Delete instance " ~ name
                    ~ " with all data, users and backups permanently? This can't be undone."))
                p.act({ p.api.request("DELETE", "/api/v1/cloud/instances/" ~ seg(name)); });
        });
    }
    if (client.me.can("monitor"))
        actions ~= PageAction("Advisors", (p) {
            auto name = p.selection("Name");
            if (!name.length)
                return;
            p.attempt({
                auto r = p.api.request("GET", "/api/v1/cloud/instances/" ~ seg(name) ~ "/advisors");
                string text;
                foreach (x; r.arrayNoRef)
                    text ~= format("• [%s] %s\n  %s\n", x["severity"].str, x["title"].str, x["detail"].str);
                showMessage(p.parent, text.length ? text : "No recommendations yet: the instance needs metrics first.", false);
            });
        });
    return new ResourcePage(client, window, signedOut, "Instances", "/api/v1/cloud/instances",
        ["name", "status", "performanceClass", "memoryGb", "vcpus", "storageGb", "nseEnabled", "ecnNodes", "users",
        "region", "createdAt"], ["Name", "Status", "Class", "Memory GB", "vCPUs", "Storage GB", "NSE", "ECN", "Users",
        "Region", "Created (UTC)"], actions);
}

// --- Überwachung ---

final class MonitoringPage : ResourcePage {
    this(HdbClient client, Window window, void delegate() signedOut) {
        PageAction[] actions = [
            PageAction("Issue summary", (p) {
                p.attempt({
                    showMessage(p.parent, p.api.request("GET", "/api/v1/monitoring/issues")["text"].str, false);
                });
            })
        ];
        if (client.me.can("manageWorkloads")) {
            actions ~= PageAction("Trace settings", (p) {
                JSONValue s;
                if (!p.attempt({ s = p.api.request("GET", "/api/v1/monitoring/trace-settings"); }))
                    return;
                auto f = new FormDialog(p.parent, "Trace settings", "Save");
                f.flag("sql", "Trace all statements (SQL trace)", s["sqlTrace"].boolean)
                    .flag("errors", "Trace failed statements", s["traceErrors"].boolean)
                    .text("expensive", "Expensive statement threshold (ms, 0: off)", s["expensiveThresholdMs"].integer.to!string)
                    .text("max", "Entries kept", s["maxEntries"].integer.to!string);
                scope (exit)
                    f.close();
                if (f.run())
                    p.act({
                        p.api.request("PUT", "/api/v1/monitoring/trace-settings", obj([
                                "sqlTrace": JSONValue(f.checked("sql")), "traceErrors": JSONValue(f.checked("errors")),
                                "expensiveThresholdMs": JSONValue(number(f["expensive"])),
                                "maxEntries": JSONValue(number(f["max"], 2000))
                            ]));
                    });
            });
            actions ~= PageAction("Clear trace", (p) {
                if (confirm(p.parent, "Delete all trace entries?"))
                    p.act({ p.api.request("DELETE", "/api/v1/monitoring/traces"); });
            });
        }
        super(client, window, signedOut, "Monitoring", "/api/v1/monitoring/traces?limit=500",
            ["time", "kind", "user", "durationMs", "rows", "workloadClass", "statement", "error"],
            ["Time (UTC)", "Kind", "User", "ms", "Rows", "Workload", "Statement", "Error"], actions);
    }

    override void refresh() {
        run({
            auto o = client.request("GET", "/api/v1/monitoring");
            auto c = o["current"];
            info.setText(format("%s statements, %s errors, %s expensive, %s workload violations since start · "
                    ~ "current interval: %s statements, avg %.1f ms · %s samples · %s cores", o["statements"].integer,
                    o["errors"].integer, o["expensive"].integer, o["violations"].integer, c["statements"].integer,
                    num(c["avgMs"]), o["samples"].arrayNoRef.length, o["workers"].integer));
        });
        super.refresh();
    }

    private static double num(JSONValue v) {
        return v.type == JSONType.float_ ? v.floating : v.type == JSONType.integer ? cast(double) v.integer : 0;
    }
}

// --- Advisor ---

ResourcePage advisorsPage(HdbClient client, Window window, void delegate() signedOut) {
    return new ResourcePage(client, window, signedOut, "Advisors", "/api/v1/advisors",
        ["advisor", "severity", "target", "title", "action", "detail"],
        ["Advisor", "Severity", "Target", "Recommendation", "Action", "Details"], [
            PageAction("Run all advisors", (p) {
                p.act({ p.api.request("POST", "/api/v1/advisors/run", obj(null)); });
            }),
            PageAction("Details", (p) {
                auto d = p.selection("Details");
                if (d.length)
                    showMessage(p.parent, p.grid.selected("Recommendation") ~ "\n\n" ~ d ~ "\n\nAction: "
                        ~ p.grid.selected("Action"), false);
            })
        ]);
}

// --- Workloads ---

ResourcePage workloadsPage(HdbClient client, Window window, void delegate() signedOut) {
    PageAction[] actions;
    if (client.me.can("manageWorkloads")) {
        actions ~= PageAction("Class…", (p) {
            auto f = new FormDialog(p.parent, "Workload class", "Save");
            f.text("name", "Name", p.grid.selected("Name")).text("priority", "Priority (0-9)", "5")
                .text("timeout", "Statement timeout (s, 0: none)", "0").text("memory", "Statement memory limit (MB)", "0")
                .text("limit", "Total statement limit", "0").text("threads", "Statement thread limit", "0")
                .flag("enabled", "Enabled", true);
            scope (exit)
                f.close();
            if (f.run())
                p.act({
                    p.api.request("PUT", "/api/v1/workloads/classes/" ~ seg(f["name"]), obj([
                            "priority": JSONValue(number(f["priority"], 5)),
                            "statementTimeoutSeconds": JSONValue(number(f["timeout"])),
                            "statementMemoryLimitMb": JSONValue(number(f["memory"])),
                            "totalStatementLimit": JSONValue(number(f["limit"])),
                            "statementThreadLimit": JSONValue(number(f["threads"])),
                            "enabled": JSONValue(f.checked("enabled"))
                        ]));
                });
        });
        actions ~= PageAction("Delete class", (p) {
            auto name = p.selection("Name");
            if (name.length && confirm(p.parent, "Delete workload class " ~ name ~ "?"))
                p.act({ p.api.request("DELETE", "/api/v1/workloads/classes/" ~ seg(name)); });
        });
        actions ~= PageAction("Map user/role…", (p) {
            auto f = new FormDialog(p.parent, "Workload mapping", "Save");
            f.text("name", "Mapping name").text("class", "Workload class", p.grid.selected("Name"))
                .text("user", "User (optional)").text("role", "Role (optional)")
                .note("A user mapping wins over a role mapping; with several matches the highest priority wins.");
            scope (exit)
                f.close();
            if (f.run())
                p.act({
                    p.api.request("PUT", "/api/v1/workloads/mappings/" ~ seg(f["name"]), obj([
                            "workloadClass": JSONValue(f["class"]), "userName": JSONValue(f["user"]),
                            "roleName": JSONValue(f["role"])
                        ]));
                });
        });
    }
    return new WorkloadsPage(client, window, signedOut, actions);
}

final class WorkloadsPage : ResourcePage {
    this(HdbClient client, Window window, void delegate() signedOut, PageAction[] actions) {
        super(client, window, signedOut, "Workloads", "/api/v1/workloads/classes",
            ["name", "priority", "statementTimeoutSeconds", "statementMemoryLimitMb", "totalStatementLimit",
            "statementThreadLimit", "enabled"], ["Name", "Priority", "Timeout s", "Memory MB", "Statements",
            "Threads", "Enabled"], actions);
    }

    override void refresh() {
        run({
            auto m = client.request("GET", "/api/v1/workloads/mappings");
            string[] lines;
            foreach (x; m.arrayNoRef)
                lines ~= format("%s → %s (%s)", x["name"].str, x["workloadClass"].str,
                    x["userName"].str.length ? "user " ~ x["userName"].str : "role " ~ x["roleName"].str);
            info.setText(lines.length ? "Mappings: " ~ lines.join(" · ") : "No mappings yet.");
        });
        super.refresh();
    }
}

// --- Calculation Views ---

ResourcePage viewsPage(HdbClient client, Window window, void delegate() signedOut) {
    PageAction[] actions = [
        PageAction("Preview", (p) {
            auto name = p.selection("Name");
            if (!name.length)
                return;
            p.attempt({
                auto d = p.api.request("GET", "/api/v1/views/" ~ seg(name) ~ "/data?top=50");
                string[] cols;
                foreach (c; d["columns"].arrayNoRef)
                    cols ~= c.str;
                auto g = jsonGrid(d["rows"], cols);
                string text = cols.join(" | ") ~ "\n";
                foreach (r; g.rows)
                    text ~= r.join(" | ") ~ "\n";
                showMessage(p.parent, text, false);
            });
        }),
        PageAction("SQL", (p) {
            auto name = p.selection("Name");
            if (name.length)
                p.attempt({
                    showMessage(p.parent, p.api.request("GET", "/api/v1/views/" ~ seg(name) ~ "/sql")["sql"].str, false);
                });
        })
    ];
    if (client.me.can("manageViews")) {
        actions ~= PageAction("New view…", (p) {
            auto f = new FormDialog(p.parent, "Calculation view", "Create");
            f.text("name", "Name").text("label", "Label").text("base", "Base table")
                .text("attributes", "Attributes (col[:LABEL], comma separated)")
                .text("measures", "Measures (sum|count|avg|min|max|countDistinct(col)[:LABEL], …)")
                .text("filter", "Filter (WHERE condition, optional)")
                .note("Joins and descriptions: create the view via REST or hdb-cli cloud views create FILE.json.");
            scope (exit)
                f.close();
            if (!f.run())
                return;
            p.act({
                JSONValue[] attrs, measures;
                foreach (a; f["attributes"].split(",")) {
                    auto parts = a.strip.split(":");
                    if (parts.length && parts[0].strip.length)
                        attrs ~= obj(["column": JSONValue(parts[0].strip),
                                "label": JSONValue(parts.length > 1 ? parts[1].strip : "")]);
                }
                foreach (m; f["measures"].split(",")) {
                    auto parts = m.strip.split(":");
                    auto spec = parts.length ? parts[0].strip : "";
                    auto open = spec.length ? spec.indexOfChar('(') : -1;
                    if (open <= 0 || spec[$ - 1] != ')')
                        continue;
                    measures ~= obj(["aggregation": JSONValue(spec[0 .. open]), "column": JSONValue(spec[open + 1 .. $ - 1]),
                            "label": JSONValue(parts.length > 1 ? parts[1].strip : "")]);
                }
                p.api.request("POST", "/api/v1/views", obj([
                        "name": JSONValue(f["name"]), "label": JSONValue(f["label"]), "baseTable": JSONValue(f["base"]),
                        "attributes": JSONValue(attrs), "measures": JSONValue(measures), "filter": JSONValue(f["filter"])
                    ]));
            });
        });
        actions ~= PageAction("Delete", (p) {
            auto name = p.selection("Name");
            if (name.length && confirm(p.parent, "Delete calculation view " ~ name ~ "?"))
                p.act({ p.api.request("DELETE", "/api/v1/views/" ~ seg(name)); });
        });
    }
    return new ResourcePage(client, window, signedOut, "Calculation views", "/api/v1/views",
        ["name", "viewType", "label", "baseTable", "outputColumns", "filter", "updatedAt"],
        ["Name", "Type", "Label", "Base table", "Output", "Filter", "Changed (UTC)"], actions);
}

private ptrdiff_t indexOfChar(string s, char c) {
    foreach (i, ch; s)
        if (ch == c)
            return i;
    return -1;
}

// --- Bindungen ---

ResourcePage bindingsPage(HdbClient client, Window window, void delegate() signedOut) {
    return new ResourcePage(client, window, signedOut, "Bindings", "/api/v1/bindings",
        ["name", "application", "user", "role", "createdAt", "createdBy"],
        ["Name", "Application", "Technical user", "Role", "Created (UTC)", "By"], [
            PageAction("Bind application…", (p) {
                auto f = new FormDialog(p.parent, "Bind application", "Bind");
                f.text("name", "Binding name").text("application", "Application").text("role", "Role", "editor");
                scope (exit)
                    f.close();
                if (!f.run())
                    return;
                JSONValue r;
                if (p.act({
                        r = p.api.request("POST", "/api/v1/bindings", obj(["name": JSONValue(f["name"]),
                            "application": JSONValue(f["application"]), "role": JSONValue(f["role"])]));
                    }))
                    showMessage(p.parent, "Store these credentials now, the password is not shown again:\n\n"
                        ~ r["credentials"].toPrettyString, false);
            }),
            PageAction("Unbind", (p) {
                auto name = p.selection("Name");
                if (name.length && confirm(p.parent, "Unbind " ~ name ~ "? Its technical user is deleted."))
                    p.act({ p.api.request("DELETE", "/api/v1/bindings/" ~ seg(name)); });
            })
        ]);
}

// --- Datenprodukte ---

ResourcePage productsPage(HdbClient client, Window window, void delegate() signedOut) {
    PageAction[] actions;
    if (client.me.can("manageDataProducts")) {
        actions ~= PageAction("Install", (p) {
            auto id = p.selection("Id");
            if (id.length)
                p.act({ p.api.request("POST", "/api/v1/dataproducts/" ~ seg(id) ~ "/install"); });
        });
        actions ~= PageAction("Uninstall", (p) {
            auto id = p.selection("Id");
            if (id.length && confirm(p.parent, "Uninstall " ~ id ~ "? Its tables are dropped."))
                p.act({ p.api.request("DELETE", "/api/v1/dataproducts/" ~ seg(id) ~ "/install"); });
        });
    }
    return new ResourcePage(client, window, signedOut, "Data products", "/api/v1/dataproducts",
        ["id", "version", "title", "provider", "rows", "installed", "description"],
        ["Id", "Version", "Title", "Provider", "Rows", "Installed", "Description"], actions);
}

// --- Assistent ---

final class AssistantPage : Page {
    private Box box;
    private TextView transcript;
    private Entry input;

    this(HdbClient client, Window window, void delegate() signedOut) {
        super(client, window, signedOut);
        box = pageBox();
        auto intro = new Label("Ask for status, maintenance, backups, issue summaries, advisors or a guide. "
                ~ "Chain tasks with ';' or 'then', e.g. \"merge delta; checkpoint; summarize issues\".");
        intro.setLineWrap(true);
        intro.setXalign(0);
        box.packStart(intro, false, false, 0);
        transcript = new TextView();
        transcript.setEditable(false);
        transcript.setWrapMode(WrapMode.WORD);
        transcript.setMonospace(true);
        auto scroll = new ScrolledWindow();
        scroll.setPolicy(PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
        scroll.add(transcript);
        box.packStart(scroll, true, true, 0);
        auto bar = new Box(Orientation.HORIZONTAL, 6);
        input = new Entry();
        input.setPlaceholderText("status; run advisors");
        input.addOnActivate((Entry) { ask(); });
        bar.packStart(input, true, true, 0);
        bar.packStart(button("Ask", &ask), false, false, 0);
        box.packStart(bar, false, false, 0);
    }

    override Widget widget() {
        return box;
    }

    override string title() {
        return "Assistant";
    }

    override void refresh() {
    }

    private void ask() {
        auto message = input.getText().strip;
        if (message.length == 0)
            return;
        run({
            auto r = client.request("POST", "/api/v1/assistant", JSONValue(["message": JSONValue(message)]));
            auto buffer = transcript.getBuffer();
            auto previous = buffer.getText();
            buffer.setText(previous ~ (previous.length ? "\n\n" : "") ~ "> " ~ message ~ "\n" ~ r["text"].str);
            input.setText("");
        });
    }
}

/// Aufbewahrung der Sicherungen (für die Sicherungsseite).
void editBackupRetention(HdbClient client, Window window, void delegate() signedOut) {
    auto f = new FormDialog(window, "Backup retention", "Save");
    f.text("days", "Keep scheduled and safety backups for (days, 0-215)", "15")
        .note("Older automatic backups are deleted; the newest scheduled backup always stays. 0 keeps them by count only.");
    scope (exit)
        f.close();
    if (f.run())
        guarded(window, {
            auto r = client.request("PUT", "/api/v1/backups/retention", JSONValue(["retentionDays": JSONValue(number(f["days"]))]));
            showMessage(window, format("Automatic backups are now kept for %s days.", r["retentionDays"].integer), false);
        }, signedOut);
}
