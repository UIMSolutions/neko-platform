/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Workload-Klassen und Zuordnungen eines Mandanten verwalten. Durchgesetzt werden sie in MonitoredDatabases.
module neko.database.application.services.cloud.workloads;

import neko.database.application.services.cloud.common;
import neko.database.domain;
import neko.database.ports;
import std.algorithm : any, countUntil, filter, sort;
import std.array : array;
import std.format : format;

@safe:

final class WorkloadService : IWorkloadUseCase {
    private ICloudRepository repo;
    private CloudAudit audit;

    this(ICloudRepository repo, CloudAudit audit = CloudAudit.init) {
        this.repo = repo;
        this.audit = audit;
    }

    WorkloadClass[] listClasses(Principal actor) {
        requireAnyTenantPermission(actor, Permission.manageWorkloads, Permission.monitor);
        auto r = repo.tenantState(actor.tenant).workloadClasses;
        r.sort!((a, b) => a.name < b.name);
        return r;
    }

    WorkloadClass saveClass(Principal actor, WorkloadClass c) {
        requireTenantPermission(actor, Permission.manageWorkloads);
        return audit.run!WorkloadClass(actor, "workloads", "saveWorkloadClass", c.name,
            format("priority=%s timeout=%s memoryMb=%s limit=%s", c.priority, c.statementTimeoutSeconds,
                c.statementMemoryLimitMb, c.totalStatementLimit), () {
            c.name = validObjectName(c.name, "Workload class name");
            validate(c);
            auto s = repo.tenantState(actor.tenant);
            auto at = s.workloadClasses.countUntil!(x => x.name == c.name);
            if (at >= 0)
                s.workloadClasses[at] = c;
            else
                s.workloadClasses ~= c;
            repo.saveTenantState(actor.tenant, s);
            return c;
        });
    }

    void deleteClass(Principal actor, string name) {
        requireTenantPermission(actor, Permission.manageWorkloads);
        audit.run!void(actor, "workloads", "deleteWorkloadClass", name, "", () {
            auto s = repo.tenantState(actor.tenant);
            if (!s.workloadClasses.any!(x => x.name == name))
                throw new NotFound("No workload class " ~ name);
            if (s.workloadMappings.any!(m => m.workloadClass == name))
                throw new Conflict("Workload class " ~ name ~ " is still mapped; delete its mappings first");
            s.workloadClasses = s.workloadClasses.filter!(x => x.name != name).array;
            repo.saveTenantState(actor.tenant, s);
        });
    }

    WorkloadMapping[] listMappings(Principal actor) {
        requireAnyTenantPermission(actor, Permission.manageWorkloads, Permission.monitor);
        auto r = repo.tenantState(actor.tenant).workloadMappings;
        r.sort!((a, b) => a.name < b.name);
        return r;
    }

    WorkloadMapping saveMapping(Principal actor, WorkloadMapping m) {
        requireTenantPermission(actor, Permission.manageWorkloads);
        return audit.run!WorkloadMapping(actor, "workloads", "saveWorkloadMapping", m.name,
            "class=" ~ m.workloadClass, () {
            auto s = repo.tenantState(actor.tenant);
            validate(m, s.workloadClasses);
            auto at = s.workloadMappings.countUntil!(x => x.name == m.name);
            if (at >= 0)
                s.workloadMappings[at] = m;
            else
                s.workloadMappings ~= m;
            repo.saveTenantState(actor.tenant, s);
            return m;
        });
    }

    void deleteMapping(Principal actor, string name) {
        requireTenantPermission(actor, Permission.manageWorkloads);
        audit.run!void(actor, "workloads", "deleteWorkloadMapping", name, "", () {
            auto s = repo.tenantState(actor.tenant);
            if (!s.workloadMappings.any!(x => x.name == name))
                throw new NotFound("No workload mapping " ~ name);
            s.workloadMappings = s.workloadMappings.filter!(x => x.name != name).array;
            repo.saveTenantState(actor.tenant, s);
        });
    }
}
