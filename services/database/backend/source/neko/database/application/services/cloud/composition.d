/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Verdrahtet alle Cloud-Dienste aus ihren Ports. app.d und die Tests bauen die Cloud-Funktionen nur hierüber.
module neko.database.application.services.cloud.composition;

import neko.database.application.services.cloud.analytics;
import neko.database.application.services.cloud.assistant;
import neko.database.application.services.cloud.common;
import neko.database.application.services.cloud.instances;
import neko.database.application.services.cloud.integration;
import neko.database.application.services.cloud.monitoring;
import neko.database.application.services.cloud.workloads;
import neko.database.domain;
import neko.database.ports;

@safe:

/// Abhängigkeiten der Cloud-Dienste.
struct CloudDependencies {
    ISqlUseCase sql; // abgesichert (und auditiert); wird von MonitoredDatabases umhüllt
    IBackupUseCase backups;
    IAccessUseCase access;
    ITenantUseCase tenants; // ohne eigenes Audit: die Instanzdienste zeichnen selbst auf
    ICredentialCrypto crypto;
    ICloudRepository repository;
    IMonitoringStore monitoring;
    IDataProductCatalog catalog;
    Principal delegate() @safe current;
    CloudAudit audit;
    string region = "local";
    AdvisorSettings advisorSettings;
}

final class CloudServices {
    /// Der SQL-Kern für alle Adapter: misst, traced und setzt Workload-Grenzen durch.
    MonitoredDatabases sql;
    InstanceService instances;
    WorkloadService workloads;
    MonitoringService monitoring;
    AdvisorService advisors;
    CalcViewService views;
    BindingService bindings;
    DataProductService products;
    AssistantService assistant;

    this(CloudDependencies d) {
        sql = new MonitoredDatabases(d.sql, d.repository, d.monitoring, d.current);
        instances = new InstanceService(d.tenants, d.repository, d.monitoring, d.region, d.audit);
        workloads = new WorkloadService(d.repository, d.audit);
        monitoring = new MonitoringService(sql, d.repository, d.monitoring, d.audit);
        advisors = new AdvisorService(sql, d.repository, d.monitoring, d.advisorSettings);
        views = new CalcViewService(sql, d.repository, d.audit);
        bindings = new BindingService(d.access, d.crypto, d.repository, d.audit);
        products = new DataProductService(sql, d.catalog, d.repository, d.audit);
        assistant = new AssistantService(d.audit);
        assistant.instances = instances;
        assistant.sql = sql;
        assistant.backups = d.backups;
        assistant.monitoring = monitoring;
        assistant.advisors = advisors;
        assistant.workloads = workloads;
        assistant.views = views;
        assistant.products = products;
        assistant.bindings = bindings;
    }
}
