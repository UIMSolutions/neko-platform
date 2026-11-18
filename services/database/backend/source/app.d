/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module app;

import neko.database;
import neko.database.infrastructure.configuration : DatabaseConfig, loadConfig;
import neko.database.infrastructure.gateway : GatewayConfigFile, GatewayProxy;
import neko.database.infrastructure.workers : PeriodicJob, Workers;

/// Composition Root: einziger Ort, an dem Adapter und Kern verdrahtet werden.
/// Einstellungen: config/default.json → Umgebungsvariablen → VCAP_SERVICES (siehe infrastructure.configuration).
/// HDB_MODE wählt die Betriebsart: multi (Standard), single oder gateway. Eingebettet ist keine Betriebsart des
/// Servers, sondern die Bibliothek (dub build --config=library, Modul neko.database.embedded).
int main() @safe {
    DatabaseConfig config;
    ServerMode mode;
    try {
        config = loadConfig();
        mode = parseServerMode(config.mode);
    } catch (Exception e)
        return fail("%s", e.msg);
    if (mode == ServerMode.gateway)
        return runGateway(config);
    immutable single = mode == ServerMode.single;

    // Eine Datenbank je Mandant unter tenantsDir. Daten aus der Zeit vor den Mandanten ziehen beim ersten Start
    // in den Mandanten default.
    immutable migrated = migrateLegacyData(config.tenantsDir, config.tablesDir, config.dataFile, config.backupDir);
    auto registry = new TenantRegistry(new FileTenantStore(config.tenantsFile));

    // Protokolle: Audit, Anwendung, Ereignisse. Das Anwendungsprotokoll gehört dem Bereich des Servers.
    immutable serverScope = single ? defaultTenant : systemTenant;
    LogService logs;
    try
        logs = new LogService(new FileLogStore(config.logDir), new FileLogSettingsStore(config.logSettingsFile),
            serverScope, (string s) => s == systemTenant || registry.has(s));
    catch (Exception e)
        return fail("Protokolle nicht lesbar: %s", e.msg);
    auto capture = new ApplicationLogCapture(logs);
    capture.start();
    scope (exit)
        capture.stop();
    if (migrated)
        logs.event(serverScope, "server", LogSeverity.info, "Data from before tenants moved to the tenant " ~ defaultTenant);
    auto userStore = new FileUserStore(config.usersFile);
    auto knownUsers = userStore.load();
    immutable firstStart = registry.all().length == 0 && knownUsers.length == 0;
    immutable legacyUsers = knownUsers.canFind!(u => u.tenant == defaultTenant);
    if (!registry.has(defaultTenant) && (firstStart || migrated || legacyUsers || single))
        registry.put(Tenant(defaultTenant, "Default", true));
    if (single) {
        auto others = registry.all().filter!(t => t.name != defaultTenant).map!(t => t.name).array;
        if (others.length)
            return fail("HDB_MODE=single needs a server with only the tenant '%s', but there are also: %s. "
                ~ "Move or delete these tenants first, or run with HDB_MODE=multi.", defaultTenant, others.join(", "));
    }

    auto crypto = new OpensslCredentialCrypto;
    auto access = new AccessService(userStore, crypto, null, &registry.isActive, new FileRoleStore(config.rolesFile),
        null, &registry.networks);
    void announce(string tenant, string name, string generated) {
        if (generated.length) {
            logs.event(serverScope, "server", LogSeverity.warning, "Initial administrator '" ~ name
                    ~ "' created in tenant '" ~ tenant ~ "' with a generated password");
            logWarn("Erster Start: Benutzer '%s' im Mandanten '%s' mit Passwort '%s' angelegt. Bitte unter /admin/account ändern.",
                name, tenant, generated);
        }
    }

    if (registry.has(defaultTenant))
        announce(defaultTenant, config.adminUser, access.bootstrap(defaultTenant, config.adminUser, config.adminPassword));
    if (single)
        access.restrictTo(defaultTenant);
    else
        announce(systemTenant, config.systemAdminUser, access.bootstrap(systemTenant, config.systemAdminUser,
                config.systemAdminPassword));

    // Kern: eine Datenbank je Mandant, Replikation zwischen Servern
    auto storage = new FileTenantStorage(config.tenantsDir);
    auto replicationClient = new HttpReplicationClient(config.replicationHostList);
    auto databases = new TenantDatabases(storage, toDelegate(&currentPrincipal), replicationClient,
        cast(size_t) config.replicationRetain);
    foreach (t; registry.all())
        databases.open(t.name);
    databases.events = logs;
    auto tenantService = new TenantService(registry, access, databases, storage);

    // Audit: jede Aktion auf jedem Weg (REST, OData, Admin-Web, Unix-Socket) wird gleich erfasst
    auto principalOf = toDelegate(&currentPrincipal);
    auto addressOf = toDelegate(&currentClientAddress);
    auto audited = new AuditedDatabases(databases, databases, databases, logs, principalOf, addressOf);
    IAccessUseCase auditedAccess = new AuditedAccess(access, logs, principalOf, addressOf);
    ITenantUseCase tenants = new AuditedTenants(tenantService, logs, addressOf);
    IBackupUseCase backups = audited;

    // Cloud-Funktionen: Instanzen, Workloads, Überwachung, Advisor, Views, Bindungen, Datenprodukte, Assistent.
    // Ihr SQL-Kern umhüllt den auditierten: alle Adapter bekommen cloud.sql und werden damit gemessen.
    CloudDependencies deps;
    deps.sql = audited;
    deps.backups = backups;
    deps.access = auditedAccess;
    deps.tenants = tenantService;
    deps.crypto = crypto;
    deps.repository = new CloudRepository(new FileCloudStateStore(config.cloudFile));
    deps.monitoring = new MemoryMonitoringStore;
    deps.catalog = new DataProductCatalog(config.dataProductsDir);
    deps.current = principalOf;
    deps.audit = CloudAudit(logs, addressOf);
    deps.region = config.region;
    auto cloud = new CloudServices(deps);
    ISqlUseCase secured = cloud.sql;

    // Hintergrundaufgaben
    auto workers = new Workers;
    workers.schedule(PeriodicJob("Geplante Sicherung", config.backupTickSeconds.seconds, () {
            auto e = databases.tick();
            return e.length ? [e] : null;
        }));
    workers.schedule(PeriodicJob("Replikation", 1.seconds, () => databases.replicationTick()));
    workers.schedule(PeriodicJob("Aufräumen der Protokolle", 1.hours, () {
            logs.maintain();
            return cast(string[]) null;
        }, true));
    workers.schedule(PeriodicJob("Messpunkte", config.monitorTickSeconds.seconds, () {
            cloud.sql.sample(databases);
            return cast(string[]) null;
        }));
    scope (exit)
        workers.stop();

    auto router = new URLRouter;
    new SecurityGate(access, parseNetworks(config.trustedProxyList)).register(router); // vor allen anderen Routen
    registerServerInfo(router, mode);
    new SqlRestApi(secured).register(router);
    registerHdbRestApi(router, secured, auditedAccess, backups, tenants, audited, principalOf, logs);
    CloudUseCases useCases;
    useCases.instances = cloud.instances;
    useCases.workloads = cloud.workloads;
    useCases.monitoring = cloud.monitoring;
    useCases.advisors = cloud.advisors;
    useCases.views = cloud.views;
    useCases.bindings = cloud.bindings;
    useCases.products = cloud.products;
    useCases.assistant = cloud.assistant;
    useCases.publicUrl = config.publicUrl;
    registerCloudRestApi(router, useCases, principalOf);
    new CloudODataController(useCases, principalOf).register(router); // vor /odata/v4/*: eine Tabelle "cloud" bleibt verdeckt
    new ODataController(secured).register(router);
    auto adminUi = new SqlAdminUi(secured, auditedAccess, backups, tenants, audited);
    adminUi.singleTenant = single;
    adminUi.register(router);

    // Fiori-Frontend (SAP Fiori 3 / OpenUI5) aus frontendDir; auf BTP liefert es der Approuter aus
    if (config.frontendDir.length && existsDir(config.frontendDir)) {
        router.get("/ui5", staticRedirect("/ui5/"));
        auto files = new HTTPFileServerSettings("/ui5");
        router.get("/ui5/*", serveStaticFiles(config.frontendDir, files));
    }
    router.get("/*", serveStaticFiles(config.publicDir));

    listenHTTP(serverSettings(config), router);
    logInfo("Betriebsart: %s, %s Kerne für parallele Auswertungen", modeName(mode), totalCPUs);
    logs.event(serverScope, "server", LogSeverity.info, "Server started (mode " ~ modeName(mode) ~ ", "
            ~ registry.all().length.to!string ~ " tenants)");

    // Optional: lokale Clients ohne TCP. Anmeldung und Rollen gelten wie über HTTP
    UnixServer unixServer;
    if (config.unixSocket.length) {
        unixServer = new UnixServer(config.unixSocket, [new UnixController(secured, auditedAccess)]);
        unixServer.start();
    }

    immutable status = runApplication();

    if (unixServer !is null)
        unixServer.stop();
    logs.event(serverScope, "server", LogSeverity.info, "Server stopped");
    return status;
}

private bool existsDir(string path) @trusted {
    import std.file : exists, isDir;

    return exists(path) && isDir(path);
}

private size_t totalCPUs() @trusted {
    import std.parallelism : totalCPUs;

    return totalCPUs;
}

private HTTPServerSettings serverSettings(DatabaseConfig config) @safe {
    auto settings = new HTTPServerSettings;
    settings.port = config.port;
    settings.bindAddresses = [config.host];
    settings.maxRequestSize = config.maxRequestMb * 1024 * 1024; // hochgeladene Sicherungen
    return settings;
}

/// Verteilter Betrieb: dieser Prozess hat keine Daten und keine Benutzer, er leitet jede Anfrage an den hdb-Server
/// des Mandanten weiter (gatewayConfig, siehe neko.database.infrastructure.gateway.routes).
private int runGateway(DatabaseConfig config) @safe {
    GatewayConfigFile gateway;
    try
        gateway = new GatewayConfigFile(config.gatewayConfig);
    catch (Exception e)
        return fail("Gateway: Konfiguration %s nicht lesbar: %s", config.gatewayConfig, e.msg);
    auto router = new URLRouter;
    registerServerInfo(router, ServerMode.gateway);
    new GatewayProxy(&gateway.current, config.gatewayConnectSeconds.seconds, config.gatewayReadSeconds.seconds)
        .register(router);
    listenHTTP(serverSettings(config), router);
    logInfo("Betriebsart: gateway, Backends: %s", gateway.current().backendIds);
    return runApplication();
}

/// Startfehler: Meldung ins Log, Exit-Code 1 (für systemd, Docker und Skripte).
private int fail(Args...)(string format, Args args) @safe {
    logError(format, args);
    return 1;
}
