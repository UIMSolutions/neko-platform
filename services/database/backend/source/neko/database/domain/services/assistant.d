/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Virtueller Assistent für die Datenbankverwaltung: versteht kurze Aufträge in Englisch oder Deutsch und zerlegt
/// sie in Absichten. Mehrere Aufträge in einer Nachricht (durch ';', Zeilenumbruch, "then" oder "dann" getrennt)
/// werden als Stapel nacheinander ausgeführt. Ausgeführt wird in der Anwendungsschicht, mit den Rechten des
/// Fragenden; der Parser selbst ändert nichts.
module neko.database.domain.services.assistant;

import std.algorithm : any, canFind, filter, map;
import std.array : array, join, split;
import std.regex : ctRegex, matchFirst, regex, splitter;
import std.string : strip, toLower;

@safe:

enum Intent {
    help,
    guide, // Schritt-für-Schritt-Anleitung zu einem Thema
    instanceStatus,
    startInstance,
    stopInstance,
    listTables,
    statistics,
    createBackup,
    listBackups,
    mergeDelta,
    checkpoint,
    expensiveStatements,
    issueSummary,
    runAdvisors,
    listWorkloads,
    listViews,
    listDataProducts,
    installDataProduct,
    listBindings,
    unknown
}

struct AssistantIntent {
    Intent intent;
    string argument; // Instanz, Thema, Datenprodukt oder Bezeichnung
    string text; // ursprünglicher Auftrag
}

/// Themen der Anleitungen.
immutable string[] guideTopics = ["restore", "backup", "instance", "scale", "workload", "view", "binding",
    "dataproduct", "monitoring", "advisor"];

/// Zerlegt eine Nachricht in einzelne Aufträge.
string[] splitBatch(string message) {
    string[] parts;
    foreach (p; message.splitter(regex(`;|\n|\s+(?:and then|then|und dann|dann)\s+`, "i")))
        if (p.strip.length)
            parts ~= p.strip;
    return parts;
}

AssistantIntent[] parseMessage(string message) {
    return splitBatch(message).map!(p => parseCommand(p)).array;
}

AssistantIntent parseCommand(string command) {
    auto t = command.strip.toLower;
    bool has(string[] words...) {
        return words.any!(w => t.canFind(w));
    }

    auto r = AssistantIntent(Intent.unknown, "", command.strip);
    if (t.length == 0 || t == "?" || has("help", "hilfe", "what can you", "was kannst"))
        return r.with_(Intent.help);
    if (has("how do i", "how to", "wie kann ich", "wie geht", "guide", "anleitung", "explain", "erkläre")) {
        foreach (topic; guideTopics)
            if (t.canFind(topic) || (topic == "dataproduct" && has("data product", "datenprodukt"))
                    || (topic == "view" && has("calculation")) || (topic == "scale" && has("resize", "größe")))
                return r.with_(Intent.guide, topic);
        return r.with_(Intent.guide, "");
    }
    if (has("start instance", "starte instanz", "activate instance")) // vor "status"
        return r.with_(Intent.startInstance, lastWord(command));
    if (has("stop instance", "stoppe instanz", "deactivate instance"))
        return r.with_(Intent.stopInstance, lastWord(command));
    if (has("instance", "instanz", "status", "health", "zustand"))
        return r.with_(Intent.instanceStatus);
    if (has("install") && has("product", "produkt"))
        return r.with_(Intent.installDataProduct, lastWord(command));
    if (has("data product", "datenprodukt", "products", "produkte"))
        return r.with_(Intent.listDataProducts);
    if (has("backup", "sicherung", "sichere")) {
        if (has("list", "show", "zeige", "liste", "which", "welche"))
            return r.with_(Intent.listBackups);
        auto m = matchFirst(command, ctRegex!(`(?:labell?ed|label|named|called|bezeichnung|namens)\s+(\S+)`, "i"));
        return r.with_(Intent.createBackup, m.empty ? "" : m[1]);
    }
    if (has("merge"))
        return r.with_(Intent.mergeDelta);
    if (has("checkpoint", "save point", "savepoint"))
        return r.with_(Intent.checkpoint);
    if (has("expensive", "slow", "langsam", "teuer", "teure"))
        return r.with_(Intent.expensiveStatements);
    if (has("issue", "problem", "error", "fehler", "diagnos", "root cause", "ursache", "summar", "zusammenfass"))
        return r.with_(Intent.issueSummary);
    if (has("advis", "recommend", "empfehl", "optimi", "tune", "index", "partition"))
        return r.with_(Intent.runAdvisors);
    if (has("workload"))
        return r.with_(Intent.listWorkloads);
    if (has("view"))
        return r.with_(Intent.listViews);
    if (has("binding", "bindung", "bound app"))
        return r.with_(Intent.listBindings);
    if (has("statistic", "statistik", "memory", "speicher", "size", "größe"))
        return r.with_(Intent.statistics);
    if (has("table", "tabelle"))
        return r.with_(Intent.listTables);
    return r;
}

/// Schritte einer Anleitung.
string[] guideSteps(string topic) {
    switch (topic) {
    case "backup":
        return ["Open Backups (Fiori: Backups, hdb-admin: Backups, CLI: hdb-cli cloud backups create).",
            "Create a manual backup with an optional label; scheduled backups run every interval hours.",
            "Set the retention: scheduled backups older than the retention days (up to 215 days, about 7 months) are deleted automatically.",
            "Download a backup to keep a copy outside the server."];
    case "restore":
        return ["Pick the backup to restore in Backups.",
            "Restore replaces all tables; the current state is saved first as a safety backup.",
            "Check the tables and statistics afterwards; to undo, restore the safety backup."];
    case "instance":
        return ["Sign in as a system administrator (tenant system).",
            "Create an instance with name, memory (multiples of 16 GB), storage (at least twice the memory) and performance class.",
            "The instance gets its own database and an initial administrator; share the credentials with the tenant admin.",
            "Stop an instance to end all sessions; delete it to remove data, users and backups permanently."];
    case "scale":
        return ["Run the Performance Class Advisor after the instance has collected metrics for a while.",
            "Resize memory and storage or change the performance class on the instance (PATCH /api/v1/cloud/instances/{name}).",
            "For read peaks at certain hours, add elastic compute nodes as the ECN Advisor suggests."];
    case "workload":
        return ["Create a workload class with priority, statement timeout, memory limit and total statement limit.",
            "Map users or roles to the class; a user mapping wins over a role mapping.",
            "Watch violations in Monitoring; the issue summary explains which limit was hit."];
    case "view":
        return ["Create a calculation view on a base table, optionally with joins.",
            "Add attributes (group-by columns with labels) and measures (aggregated columns).",
            "Query it via REST (/api/v1/views/{name}/data), OData (/odata/v4/cloud/CV_{name}) or the Fiori app; table permissions still apply."];
    case "binding":
        return ["Create a binding with a name and the application it is for; it creates a technical user.",
            "Copy the credentials right away: the password is shown only once.",
            "Put the credentials into the application's environment (VCAP_SERVICES format) and use REST, OData or SQL.",
            "Delete the binding to revoke the technical user."];
    case "dataproduct":
        return ["List the data products shared to this environment.",
            "Install one: its tables are created with the prefix of the product id and filled with the shared data.",
            "Query the tables with SQL, OData or a calculation view; uninstall drops them again."];
    case "monitoring":
        return ["Monitoring shows statements, errors, average duration, memory and CPU over time.",
            "Turn on the SQL trace to record all statements, or set the expensive statement threshold.",
            "Generate an issue summary to get the suspected root cause and a resolution."];
    case "advisor":
        return ["Run the advisors: Index, NSE, Partition, Performance Class and ECN.",
            "Each recommendation names its target, the evidence and the suggested action.",
            "Apply what fits; run the advisors again after the workload has changed."];
    default:
        return ["Topics: " ~ guideTopics.join(", ") ~ ". Ask for example: \"how do I restore a backup?\""];
    }
}

/// Beispiele für die Hilfe.
immutable string[] assistantExamples = [
    "status of instances", "create a backup labeled before-release", "show expensive statements",
    "summarize issues", "run advisors", "merge delta; checkpoint", "how do I bind an application?",
    "install data product bdc.sales.orders", "stop instance acme"
];

private AssistantIntent with_(AssistantIntent r, Intent intent, string argument = "") {
    r.intent = intent;
    r.argument = argument;
    return r;
}

private string lastWord(string s) {
    auto words = s.strip.split;
    return words.length > 1 ? words[$ - 1] : "";
}

unittest {
    auto r = parseMessage("create a backup labeled nightly; merge delta then show expensive statements");
    assert(r.length == 3);
    assert(r[0].intent == Intent.createBackup);
    assert(r[1].intent == Intent.mergeDelta && r[2].intent == Intent.expensiveStatements);
    assert(parseCommand("Wie kann ich eine Sicherung wiederherstellen? restore").intent == Intent.guide);
    assert(parseCommand("how do I bind an application? binding").argument == "binding");
    assert(parseCommand("stop instance acme").argument == "acme");
    assert(parseCommand("Status der Instanzen").intent == Intent.instanceStatus);
    assert(parseCommand("install data product bdc.sales.orders").argument == "bdc.sales.orders");
    assert(parseCommand("fasse die Fehler zusammen").intent == Intent.issueSummary);
    assert(parseCommand("sing a song").intent == Intent.unknown);
}
