/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository für Instanzen und Mandantenzustände über einer JSON-Ablage. Hält den Stand im Speicher und schreibt
/// nach jeder Änderung die ganze Datei.
module neko.database.persistence.repositories.cloud;

import neko.database.domain;
import neko.database.persistence.mappers;
import neko.database.ports.repositories;
import neko.database.ports.storages : ICloudStateStore;
import std.algorithm : countUntil, filter, map, sort;
import std.array : array;

@safe:

final class CloudRepository : ICloudRepository {
    private ICloudStateStore store;
    private DatabaseInstance[] all;
    private TenantCloudState[string] tenants;

    this(ICloudStateStore store) {
        this.store = store;
        cloudStateFromJson(store.load(), all, tenants);
    }

    DatabaseInstance[] instances() {
        auto r = all.dup;
        r.sort!((a, b) => a.name < b.name);
        return r;
    }

    bool hasInstance(string name) {
        return all.countUntil!(i => i.name == name) >= 0;
    }

    DatabaseInstance instance(string name) {
        auto at = all.countUntil!(i => i.name == name);
        if (at < 0)
            throw new NotFound("No instance " ~ name);
        return all[at];
    }

    void saveInstance(DatabaseInstance instance) {
        auto at = all.countUntil!(i => i.name == instance.name);
        if (at < 0)
            all ~= instance;
        else
            all[at] = instance;
        persist();
    }

    void removeInstance(string name) {
        all = all.filter!(i => i.name != name).array;
        persist();
    }

    TenantCloudState tenantState(string tenant) {
        if (auto s = tenant in tenants)
            return copy(*s);
        return TenantCloudState.init;
    }

    void saveTenantState(string tenant, TenantCloudState state) {
        tenants[tenant] = copy(state);
        persist();
    }

    void removeTenantState(string tenant) {
        tenants.remove(tenant);
        persist();
    }

    private void persist() {
        store.save(cloudStateToJson(all, tenants));
    }

    private static TenantCloudState copy(TenantCloudState s) {
        return TenantCloudState(s.workloadClasses.dup, s.workloadMappings.dup, s.views.dup, s.bindings.dup,
            s.products.dup, s.trace);
    }
}

unittest {
    import neko.database.persistence.storages.cloud_store : MemoryCloudStateStore;
    import std.exception : assertThrown;

    auto store = new MemoryCloudStateStore;
    auto repo = new CloudRepository(store);
    repo.saveInstance(DatabaseInstance("b"));
    repo.saveInstance(DatabaseInstance("a"));
    assert(repo.instances.map!(i => i.name).array == ["a", "b"]);
    auto s = repo.tenantState("a");
    s.workloadClasses ~= WorkloadClass("ETL");
    repo.saveTenantState("a", s);
    auto again = new CloudRepository(store); // aus der Ablage
    assert(again.hasInstance("b") && again.tenantState("a").workloadClasses[0].name == "ETL");
    again.removeInstance("b");
    assertThrown!NotFound(again.instance("b"));
}
