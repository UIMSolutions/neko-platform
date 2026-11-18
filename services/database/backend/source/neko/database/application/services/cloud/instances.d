/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Instanzen bereitstellen, skalieren, starten, stoppen und löschen. Eine Instanz ist ein Mandant mit
/// Betriebsangaben: Anlegen und Löschen laufen über die Mandantenverwaltung, damit Daten, Benutzer und Sicherungen
/// genau so entstehen und verschwinden wie bisher.
module neko.database.application.services.cloud.instances;

import neko.database.application.services.cloud.common;
import neko.database.domain;
import neko.database.ports;
import std.algorithm : canFind, filter, map;
import std.array : array;
import std.format : format;

@safe:

final class InstanceService : IInstanceUseCase {
    private ITenantUseCase tenants;
    private ICloudRepository repo;
    private IMonitoringStore monitoring;
    private string region;
    private CloudAudit audit;

    this(ITenantUseCase tenants, ICloudRepository repo, IMonitoringStore monitoring, string region = "local",
        CloudAudit audit = CloudAudit.init) {
        this.tenants = tenants;
        this.repo = repo;
        this.monitoring = monitoring;
        this.region = region;
        this.audit = audit;
    }

    InstanceInfo[] listInstances(Principal actor) {
        requireSystemPermission(actor, Permission.viewInstances);
        return tenants.listTenants(actor).map!(t => info(t)).array;
    }

    InstanceInfo getInstance(Principal actor, string name) {
        requireSystemPermission(actor, Permission.viewInstances);
        return info(tenantOf(actor, name));
    }

    InstanceInfo createInstance(Principal actor, InstanceSpec spec) {
        requireSystemPermission(actor, Permission.manageInstances);
        return audit.run!InstanceInfo(actor, "instances", "createInstance", spec.name,
            format("memoryGb=%s class=%s", spec.memoryGb, enumName(spec.performanceClass)), () {
            DatabaseInstance i;
            i.name = spec.name;
            i.description = spec.description;
            i.performanceClass = spec.performanceClass;
            i.memoryGb = spec.memoryGb ? spec.memoryGb : 32;
            i.storageGb = spec.storageGb ? spec.storageGb : i.memoryGb * 4;
            i.nseEnabled = spec.nseEnabled;
            i.ecnNodes = spec.ecnNodes;
            i.region = region;
            i.createdAt = i.updatedAt = utcNow();
            i.createdBy = actor.name;
            validateSizing(i);
            if (tenants.listTenants(actor).canFind!(t => t.name == spec.name))
                throw new Conflict("Instance " ~ spec.name ~ " already exists");
            auto t = tenants.createTenant(actor, spec.name, spec.description, spec.adminName, spec.adminPassword);
            i.name = t.name; // normalisiert
            repo.saveInstance(i);
            return info(t);
        });
    }

    InstanceInfo updateInstance(Principal actor, string name, InstancePatch patch) {
        requireSystemPermission(actor, Permission.manageInstances);
        return audit.run!InstanceInfo(actor, "instances", "updateInstance", name,
            format("memoryGb=%s storageGb=%s", patch.memoryGb, patch.storageGb), () {
            auto t = tenantOf(actor, name);
            auto i = instanceOf(t);
            if (patch.hasDescription) {
                i.description = patch.description;
                t = tenants.updateTenant(actor, t.name, patch.description, t.active);
            }
            if (patch.hasSizing) {
                i.memoryGb = patch.memoryGb;
                i.storageGb = patch.storageGb ? patch.storageGb : (i.storageGb < minimumStorageGb(i.memoryGb)
                    ? minimumStorageGb(i.memoryGb) : i.storageGb);
            }
            if (patch.hasClass)
                i.performanceClass = patch.performanceClass;
            if (patch.hasNse)
                i.nseEnabled = patch.nseEnabled;
            if (patch.hasEcn)
                i.ecnNodes = patch.ecnNodes;
            validateSizing(i);
            i.updatedAt = utcNow();
            repo.saveInstance(i);
            return info(t);
        });
    }

    InstanceInfo startInstance(Principal actor, string name) {
        return setActive(actor, name, true);
    }

    InstanceInfo stopInstance(Principal actor, string name) {
        return setActive(actor, name, false);
    }

    void deleteInstance(Principal actor, string name) {
        requireSystemPermission(actor, Permission.manageInstances);
        audit.run!void(actor, "instances", "deleteInstance", name, "", () {
            auto t = tenantOf(actor, name);
            if (t.active)
                tenants.updateTenant(actor, t.name, t.label, false);
            tenants.deleteTenant(actor, t.name);
            if (repo.hasInstance(t.name))
                repo.removeInstance(t.name);
            repo.removeTenantState(t.name);
            monitoring.removeTenant(t.name);
        });
    }

    MetricSample[] instanceMetrics(Principal actor, string name) {
        requireSystemPermission(actor, Permission.monitor);
        return monitoring.samples(tenantOf(actor, name).name);
    }

    Recommendation[] instanceAdvisors(Principal actor, string name) {
        requireSystemPermission(actor, Permission.monitor);
        auto t = tenantOf(actor, name);
        AdvisorInput input;
        input.samples = monitoring.samples(t.name);
        // nur Zeit und Benutzer: Systemadministratoren sehen keine Anweisungen der Mandanten
        foreach (e; monitoring.traces(t.name)) {
            TraceEntry x;
            x.time = e.time;
            x.user = e.user;
            input.traces ~= x;
        }
        input.instance = instanceOf(t);
        input.hasInstance = true;
        input.now = utcNow();
        return runAdvisors(input, [AdvisorKind.performanceClass, AdvisorKind.ecn]);
    }

    private InstanceInfo setActive(Principal actor, string name, bool active) {
        requireSystemPermission(actor, Permission.manageInstances);
        return audit.run!InstanceInfo(actor, "instances", active ? "startInstance" : "stopInstance", name, "", () {
            auto t = tenantOf(actor, name);
            return info(tenants.updateTenant(actor, t.name, t.label, active));
        });
    }

    private TenantInfo tenantOf(Principal actor, string name) {
        foreach (t; tenants.listTenants(actor))
            if (t.name == name)
                return t;
        throw new NotFound("No instance " ~ name);
    }

    /// Mandanten aus der Zeit vor den Instanzen bekommen die Vorgaben.
    private DatabaseInstance instanceOf(TenantInfo t) {
        if (repo.hasInstance(t.name))
            return repo.instance(t.name);
        auto i = DatabaseInstance(t.name, t.label);
        i.region = region;
        return i;
    }

    private InstanceInfo info(TenantInfo t) {
        auto i = instanceOf(t);
        if (i.description.length == 0)
            i.description = t.label;
        return InstanceInfo(i, t.active ? InstanceStatus.running : InstanceStatus.stopped, i.vcpus, t.users,
            t.networks.dup);
    }
}
