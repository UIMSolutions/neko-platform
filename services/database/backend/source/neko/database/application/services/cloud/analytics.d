/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Advisor und Calculation Views eines Mandanten. Beide lesen über den abgesicherten SQL-Kern und sehen deshalb
/// nur die Tabellen, die der Fragende sehen darf.
module neko.database.application.services.cloud.analytics;

import neko.database.application.services.cloud.common;
import neko.database.domain;
import neko.database.ports;
import std.algorithm : any, canFind, countUntil, filter, map, sort;
import std.array : array, join;
import std.format : format;
import std.string : toLower;

@safe:

final class AdvisorService : IAdvisorUseCase {
    private ISqlUseCase sql;
    private ICloudRepository repo;
    private IMonitoringStore store;
    private AdvisorSettings settings;
    private Recommendation[][string] last;

    this(ISqlUseCase sql, ICloudRepository repo, IMonitoringStore store, AdvisorSettings settings = AdvisorSettings.init) {
        this.sql = sql;
        this.repo = repo;
        this.store = store;
        this.settings = settings;
    }

    Recommendation[] runAdvisors(Principal actor, AdvisorKind[] kinds) {
        requireTenantPermission(actor, Permission.monitor);
        AdvisorInput input;
        input.stats = sql.stats();
        auto visible = input.stats.map!(t => t.table.toLower).array;
        input.access = store.access(actor.tenant).filter!(a => visible.canFind(a.table)).array;
        input.samples = store.samples(actor.tenant);
        input.traces = store.traces(actor.tenant);
        if (repo.hasInstance(actor.tenant)) {
            input.instance = repo.instance(actor.tenant);
            input.hasInstance = true;
        }
        input.now = utcNow();
        auto r = .runAdvisors(input, kinds, settings);
        last[actor.tenant] = r;
        return r;
    }

    Recommendation[] recommendations(Principal actor) {
        requireTenantPermission(actor, Permission.monitor);
        if (auto r = actor.tenant in last)
            return (*r).dup;
        return runAdvisors(actor, null);
    }
}

final class CalcViewService : ICalcViewUseCase {
    private ISqlUseCase sql;
    private ICloudRepository repo;
    private CloudAudit audit;

    this(ISqlUseCase sql, ICloudRepository repo, CloudAudit audit = CloudAudit.init) {
        this.sql = sql;
        this.repo = repo;
        this.audit = audit;
    }

    CalculationView[] listViews(Principal actor) {
        requireTenantUser(actor);
        auto r = repo.tenantState(actor.tenant).views;
        r.sort!((a, b) => a.name < b.name);
        return r;
    }

    CalculationView getView(Principal actor, string name) {
        requireTenantUser(actor);
        foreach (v; repo.tenantState(actor.tenant).views)
            if (v.name.toLower == name.toLower)
                return v;
        throw new NotFound("No calculation view " ~ name);
    }

    CalculationView saveView(Principal actor, CalculationView view) {
        requireTenantPermission(actor, Permission.manageViews);
        return audit.run!CalculationView(actor, "views", "saveView", view.name, "base=" ~ view.baseTable, () {
            validate(view);
            auto tables = sql.listTables().map!(t => t.toLower).array;
            foreach (t; tablesOf(view))
                if (!tables.canFind(t.toLower))
                    throw new NotFound("Unknown table " ~ t);
            // Probelauf: Spalten, Joins und Filter müssen stimmen, bevor die View gespeichert wird
            sql.execute(toSql(view, CalcQuery("", "", 1)));
            auto s = repo.tenantState(actor.tenant);
            auto at = s.views.countUntil!(v => v.name.toLower == view.name.toLower);
            view.updatedAt = utcNow();
            if (at >= 0) {
                view.createdAt = s.views[at].createdAt;
                view.createdBy = s.views[at].createdBy;
                s.views[at] = view;
            } else {
                view.createdAt = view.updatedAt;
                view.createdBy = actor.name;
                s.views ~= view;
            }
            repo.saveTenantState(actor.tenant, s);
            return view;
        });
    }

    void deleteView(Principal actor, string name) {
        requireTenantPermission(actor, Permission.manageViews);
        audit.run!void(actor, "views", "deleteView", name, "", () {
            auto s = repo.tenantState(actor.tenant);
            if (!s.views.any!(v => v.name.toLower == name.toLower))
                throw new NotFound("No calculation view " ~ name);
            s.views = s.views.filter!(v => v.name.toLower != name.toLower).array;
            repo.saveTenantState(actor.tenant, s);
        });
    }

    QueryResult queryView(Principal actor, string name, CalcQuery query) {
        auto v = getView(actor, name);
        if (query.top == 0 || query.top > 10_000)
            query.top = 10_000;
        auto r = sql.execute(toSql(v, query));
        r.columns = outputColumns(v);
        return r;
    }

    string viewSql(Principal actor, string name, CalcQuery query) {
        return toSql(getView(actor, name), query);
    }
}
