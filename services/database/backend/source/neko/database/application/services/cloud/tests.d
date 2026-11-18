/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Zusammenspiel der Cloud-Dienste mit echten Mandanten, Benutzern und Datenbanken (Ablage in einem Temp-Verzeichnis).
module neko.database.application.services.cloud.tests;

version (unittest)  : import neko.database;
import neko.database.application.services.cloud.composition;
import std.algorithm : any, canFind, map;
import std.array : array;
import std.exception : assertThrown, collectException;
import std.file : exists, rmdirRecurse, tempDir;
import std.path : buildPath;
import std.uuid : randomUUID;

private class MemUsers : IUserStore {
    HdbUser[] saved;
    HdbUser[] load() {
        return saved;
    }

    void save(HdbUser[] users) {
        saved = users.dup;
    }
}

private class MemTenants : ITenantStore {
    Tenant[] saved;
    Tenant[] load() {
        return saved;
    }

    void save(Tenant[] tenants) {
        saved = tenants.dup;
    }
}

unittest {
    auto dir = buildPath(tempDir, "hdb-cloud-" ~ randomUUID().toString);
    scope (exit)
        if (exists(dir))
            rmdirRecurse(dir);
    Principal who;
    auto current = () @safe => who;
    auto registry = new TenantRegistry(new MemTenants);
    registry.put(Tenant(defaultTenant, "Default", true));
    auto crypto = new OpensslCredentialCrypto;
    auto access = new AccessService(new MemUsers, crypto, null, &registry.isActive);
    access.bootstrap(defaultTenant, "anna", "correct-horse-anna1");
    auto storage = new FileTenantStorage(dir);
    auto databases = new TenantDatabases(storage, current);
    databases.open(defaultTenant);
    auto tenantService = new TenantService(registry, access, databases, storage);
    auto monitoring = new MemoryMonitoringStore;
    CloudDependencies d;
    d.sql = databases;
    d.backups = databases;
    d.access = access;
    d.tenants = tenantService;
    d.crypto = crypto;
    d.repository = new CloudRepository(new MemoryCloudStateStore);
    d.monitoring = monitoring;
    d.catalog = new DataProductCatalog;
    d.current = current;
    d.region = "eu10";
    d.advisorSettings.indexMinRows = 10;
    d.advisorSettings.minSamples = 1;
    auto cloud = new CloudServices(d);

    auto sys = Principal("sys", HdbRole.admin, true, systemTenant);
    auto admin = Principal("anna", HdbRole.admin, true, defaultTenant);
    auto viewer = Principal("vic", HdbRole.viewer, true, defaultTenant);

    // --- Instanzen: anlegen, skalieren, stoppen, starten, löschen ---
    who = sys;
    auto spec = InstanceSpec("acme", "ACME Corp", "boss", "correct-horse-boss1");
    spec.memoryGb = 64;
    auto created = cloud.instances.createInstance(sys, spec);
    assert(created.instance.storageGb == 256 && created.vcpus == 4 && created.status == InstanceStatus.running);
    assert(created.instance.region == "eu10");
    assertThrown!Conflict(cloud.instances.createInstance(sys, spec));
    spec.name = "tiny";
    spec.memoryGb = 40; // kein Vielfaches von 16
    assertThrown(cloud.instances.createInstance(sys, spec));
    assertThrown!AccessDenied(cloud.instances.listInstances(admin));
    InstancePatch patch;
    patch.hasSizing = patch.hasClass = true;
    patch.memoryGb = 128;
    patch.performanceClass = PerformanceClass.compute;
    auto resized = cloud.instances.updateInstance(sys, "acme", patch);
    assert(resized.vcpus == 16 && resized.instance.storageGb == 256);
    assert(cloud.instances.stopInstance(sys, "acme").status == InstanceStatus.stopped);
    assert(cloud.instances.startInstance(sys, "acme").status == InstanceStatus.running);
    auto all = cloud.instances.listInstances(sys);
    assert(all.map!(i => i.instance.name).array == ["acme", "default"]); // default mit Vorgaben
    cloud.instances.deleteInstance(sys, "acme");
    assertThrown!NotFound(cloud.instances.getInstance(sys, "acme"));

    // --- Datenprodukt installieren und abfragen ---
    who = admin;
    auto catalog = cloud.products.catalog(admin);
    assert(catalog.length == 3 && !catalog[0].installed && catalog[0].product.tables[0].rows.length == 0);
    auto inst = cloud.products.install(admin, "bdc.sales.orders");
    assert(inst.tables == ["bdc_sales_orders__customers", "bdc_sales_orders__orders"]);
    assertThrown!Conflict(cloud.products.install(admin, "bdc.sales.orders"));
    assertThrown!NotFound(cloud.products.install(admin, "nope"));
    who = viewer;
    assertThrown!AccessDenied(cloud.products.install(viewer, "bdc.hr.workforce"));

    // --- Calculation View ---
    who = admin;
    CalculationView v;
    v.name = "REVENUE_BY_REGION";
    v.baseTable = "bdc_sales_orders__orders";
    v.baseAlias = "o";
    v.joins = [CalcJoin("bdc_sales_orders__customers", "c", false, "o.customer", "c.id")];
    v.attributes = [CalcAttribute("c.region", "REGION")];
    v.measures = [CalcMeasure("o.amount", Aggregation.sum, "REVENUE"), CalcMeasure("o.id", Aggregation.count, "ORDERS")];
    v.filter = "o.status = 'paid'";
    cloud.views.saveView(admin, v);
    auto result = cloud.views.queryView(admin, "revenue_by_region", CalcQuery("", "REVENUE desc", 10));
    assert(result.columns == ["REGION", "REVENUE", "ORDERS"] && result.rows.length == 3);
    v.baseTable = "missing";
    assertThrown!NotFound(cloud.views.saveView(admin, v));
    who = viewer;
    assert(cloud.views.queryView(viewer, "REVENUE_BY_REGION", CalcQuery.init).rows.length == 3); // viewer liest alles
    assertThrown!AccessDenied(cloud.views.deleteView(viewer, "REVENUE_BY_REGION"));

    // --- Workload-Klassen: Speichergrenze und Zuordnung über die Rolle ---
    who = admin;
    cloud.workloads.saveClass(admin, WorkloadClass("REPORTING", 3, 0, 0, 0));
    cloud.workloads.saveMapping(admin, WorkloadMapping("viewers", "REPORTING", "", "viewer"));
    assertThrown!Conflict(cloud.workloads.deleteClass(admin, "REPORTING"));
    auto tiny = WorkloadClass("REPORTING", 3, 0, 1, 0);
    cloud.workloads.saveClass(admin, tiny);
    who = viewer;
    // 60 Zeilen passen in 1 MB
    assert(cloud.sql.execute("SELECT * FROM bdc_sales_orders__orders").rows.length == 60);
    auto failure = collectException(cloud.sql.execute("SELECT * FROM nothere"));
    assert(failure !is null && cast(WorkloadLimitExceeded) failure is null); // Fehler, kein Verstoß
    who = admin;

    // --- Überwachung, Trace, Zusammenfassung ---
    auto traceSettings = cloud.monitoring.traceSettings(admin);
    traceSettings.sqlTrace = true;
    cloud.monitoring.configureTrace(admin, traceSettings);
    cloud.sql.execute("SELECT * FROM bdc_sales_orders__orders WHERE id = 3");
    assertThrown(cloud.sql.execute("SELECT * FROM still_missing"));
    auto traces = cloud.monitoring.traces(admin, TraceQuery.init);
    assert(traces.any!(t => t.kind == "sql" && t.statement.canFind("id = ?")));
    assert(traces.any!(t => t.kind == "error"));
    auto overview = cloud.monitoring.overview(admin);
    assert(overview.statements >= 3 && overview.errors >= 2 && overview.workers >= 1);
    auto issues = cloud.monitoring.issueSummary(admin);
    assert(issues.errors >= 2 && issues.text.length);
    assert(cloud.monitoring.tableAccess(admin).any!(a => a.table == "bdc_sales_orders__orders" && a.filterColumns.canFind("id")));
    cloud.sql.sample(databases);
    assert(monitoring.samples(defaultTenant).length == 1 && monitoring.samples(defaultTenant)[0].tables >= 2);
    assertThrown!AccessDenied(cloud.monitoring.overview(viewer));

    // --- Advisor ---
    auto recs = cloud.advisors.runAdvisors(admin, [AdvisorKind.index]);
    assert(recs.any!(r => r.target == "bdc_sales_orders__orders.id"));
    assert(cloud.advisors.recommendations(admin).length == recs.length);

    // --- Bindung: technischer Benutzer mit Zugangsdaten ---
    auto bound = cloud.bindings.createBinding(admin, "shop", "Web Shop", "viewer", "http://localhost:8080");
    assert(bound.binding.user == "app_shop" && bound.credentials.password.length >= 12);
    assert(access.listUsers(admin).any!(u => u.name == "app_shop" && u.role == "viewer"));
    assert(access.login(defaultTenant, "app_shop", bound.credentials.password, "127.0.0.1").token.length);
    assertThrown!Conflict(cloud.bindings.createBinding(admin, "shop", "x", "", "http://localhost"));
    cloud.bindings.deleteBinding(admin, "shop");
    assert(!access.listUsers(admin).any!(u => u.name == "app_shop"));

    // --- Assistent: Stapel mit Status, Sicherung und Anleitung ---
    auto reply = cloud.assistant.ask(admin, "status; create a backup labeled assistant; how do I restore a backup? restore");
    assert(reply.steps.length == 3 && reply.steps[0].ok && reply.steps[1].ok && reply.steps[1].text.canFind("Backup"));
    assert(reply.steps[2].text.canFind("safety backup"));
    who = viewer;
    auto denied = cloud.assistant.ask(viewer, "merge delta");
    assert(!denied.steps[0].ok);
    who = sys;
    assert(cloud.assistant.ask(sys, "status of instances").steps[0].text.canFind("1 instances"));

    // --- Deinstallieren ---
    who = admin;
    cloud.products.uninstall(admin, "bdc.sales.orders");
    assert(!cloud.sql.listTables().canFind("bdc_sales_orders__orders"));
}
