/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Eingehende Ports der Cloud-Funktionen. `actor` ist immer die anfragende Identität; jede Umsetzung prüft die
/// Rechte selbst. Instanzen gehören dem Bereich system, alles andere dem Mandanten des actors.
module neko.database.ports.usecases.cloud;

import neko.database.domain;
import vibe.data.json : Json;

@safe:

// --- Instanzen (Bereich system) ---

/// Instanz mit Zustand aus dem Mandanten.
struct InstanceInfo {
    DatabaseInstance instance;
    InstanceStatus status;
    size_t vcpus;
    size_t users;
    string[] networks;
}

/// Neue Instanz. Felder mit 0 bzw. leer übernehmen die Vorgaben.
struct InstanceSpec {
    string name, description;
    string adminName, adminPassword;
    PerformanceClass performanceClass = PerformanceClass.memory;
    size_t memoryGb = 32, storageGb;
    bool nseEnabled;
    size_t ecnNodes;
}

/// Änderung einer Instanz; nur gesetzte Felder (has*) wirken.
struct InstancePatch {
    bool hasDescription, hasSizing, hasClass, hasNse, hasEcn;
    string description;
    size_t memoryGb, storageGb;
    PerformanceClass performanceClass;
    bool nseEnabled;
    size_t ecnNodes;
}

interface IInstanceUseCase {
    InstanceInfo[] listInstances(Principal actor);
    InstanceInfo getInstance(Principal actor, string name);
    InstanceInfo createInstance(Principal actor, InstanceSpec spec);
    InstanceInfo updateInstance(Principal actor, string name, InstancePatch patch);
    InstanceInfo startInstance(Principal actor, string name);
    InstanceInfo stopInstance(Principal actor, string name);
    /// Stoppt die Instanz und löscht Daten, Benutzer und Sicherungen endgültig.
    void deleteInstance(Principal actor, string name);
    /// Messpunkte der Instanz für Systemadministratoren (ohne Daten des Mandanten).
    MetricSample[] instanceMetrics(Principal actor, string name);
    /// Performance-Class- und ECN-Advisor für eine Instanz.
    Recommendation[] instanceAdvisors(Principal actor, string name);
}

// --- Workload-Management (Mandant) ---

interface IWorkloadUseCase {
    WorkloadClass[] listClasses(Principal actor);
    /// Legt die Klasse an oder ersetzt sie.
    WorkloadClass saveClass(Principal actor, WorkloadClass c);
    /// Nur Klassen ohne Zuordnung.
    void deleteClass(Principal actor, string name);
    WorkloadMapping[] listMappings(Principal actor);
    WorkloadMapping saveMapping(Principal actor, WorkloadMapping m);
    void deleteMapping(Principal actor, string name);
}

// --- Überwachung und Diagnose (Mandant) ---

struct TraceQuery {
    string kind; // sql, expensive, error, violation; leer: alle
    string user;
    string text; // Teil der Anweisung oder Meldung
    size_t limit = 200;
}

struct MonitoringOverview {
    string tenant;
    bool hasInstance;
    InstanceInfo instance;
    MetricSample current; // laufendes Intervall
    MetricSample[] samples; // älteste zuerst
    size_t statements, errors, expensive, violations; // seit dem Start
    TraceSettings settings;
    TraceEntry[] topExpensive;
    size_t workers; // Kerne, die für parallele Auswertungen genutzt werden
}

interface IMonitoringUseCase {
    MonitoringOverview overview(Principal actor);
    TraceEntry[] traces(Principal actor, TraceQuery query);
    TraceSettings traceSettings(Principal actor);
    TraceSettings configureTrace(Principal actor, TraceSettings settings);
    void clearTraces(Principal actor);
    TableAccess[] tableAccess(Principal actor);
    /// Lesbare Zusammenfassung mit vermuteter Ursache und Lösung.
    IssueSummary issueSummary(Principal actor);
}

// --- Advisor (Mandant) ---

interface IAdvisorUseCase {
    /// Führt die Advisor aus (leer: alle) und merkt sich das Ergebnis.
    Recommendation[] runAdvisors(Principal actor, AdvisorKind[] kinds);
    /// Ergebnis des letzten Laufs.
    Recommendation[] recommendations(Principal actor);
}

// --- Calculation Views (Mandant) ---

interface ICalcViewUseCase {
    CalculationView[] listViews(Principal actor);
    CalculationView getView(Principal actor, string name);
    CalculationView saveView(Principal actor, CalculationView view);
    void deleteView(Principal actor, string name);
    /// Führt die View mit den Rechten des actors aus; die Spalten tragen die Namen der Ausgabe.
    QueryResult queryView(Principal actor, string name, CalcQuery query);
    /// Die erzeugte Anweisung, ohne sie auszuführen.
    string viewSql(Principal actor, string name, CalcQuery query);
}

// --- Bindungen (Mandant) ---

struct BindingResult {
    ServiceBinding binding;
    BindingCredentials credentials;
}

interface IBindingUseCase {
    ServiceBinding[] listBindings(Principal actor);
    /// `role` ist eine Rolle des Mandanten (Standard: editor). `baseUrl` ist die öffentliche Adresse des Servers.
    BindingResult createBinding(Principal actor, string name, string application, string role, string baseUrl);
    void deleteBinding(Principal actor, string name);
}

// --- Datenprodukte (Mandant) ---

struct DataProductInfo {
    DataProduct product; // ohne Zeilen
    size_t rows;
    bool installed;
    InstalledProduct installation;
}

interface IDataProductUseCase {
    DataProductInfo[] catalog(Principal actor);
    DataProductInfo product(Principal actor, string id);
    InstalledProduct install(Principal actor, string id);
    void uninstall(Principal actor, string id);
}

// --- Assistent ---

struct AssistantStep {
    string command;
    string intent;
    bool ok = true;
    string text;
    Json data;
}

struct AssistantReply {
    string text;
    AssistantStep[] steps;
    string[] suggestions;
}

interface IAssistantUseCase {
    /// Versteht einen oder mehrere Aufträge und führt sie mit den Rechten des actors aus.
    AssistantReply ask(Principal actor, string message);
}
