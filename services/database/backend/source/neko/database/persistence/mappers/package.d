/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Umwandlung zwischen Domänenobjekten und den Datensätzen der Ablage.
module neko.database.persistence.mappers;

import neko.database.domain;
import neko.database.persistence.records;
import neko.database.ports.repositories : TenantCloudState;
import std.algorithm : map;
import std.array : array;
import vibe.data.json : Json, deserializeJson, serializeToJson;

@safe:

InstanceRecord toRecord(DatabaseInstance i) {
    return InstanceRecord(i.name, i.description, enumName(i.performanceClass), i.memoryGb, i.storageGb, i.nseEnabled,
        i.ecnNodes, i.region, i.version_, i.createdAt, i.createdBy, i.updatedAt);
}

DatabaseInstance toDomain(InstanceRecord r) {
    DatabaseInstance i;
    i.name = r.name;
    i.description = r.description;
    i.performanceClass = parseEnum!PerformanceClass(r.performanceClass.length ? r.performanceClass : "memory");
    i.memoryGb = r.memoryGb;
    i.storageGb = r.storageGb;
    i.nseEnabled = r.nseEnabled;
    i.ecnNodes = r.ecnNodes;
    i.region = r.region;
    if (r.version_.length)
        i.version_ = r.version_;
    i.createdAt = r.createdAt;
    i.createdBy = r.createdBy;
    i.updatedAt = r.updatedAt;
    return i;
}

CalcViewRecord toRecord(CalculationView v) {
    return CalcViewRecord(v.name, v.label, v.description, enumName(v.viewType), v.baseTable, v.baseAlias,
        v.joins.map!(j => CalcJoinRecord(j.table, j.alias_, j.left, j.leftColumn, j.rightColumn)).array,
        v.attributes.map!(a => CalcAttributeRecord(a.column, a.label, a.description)).array, v.measures.map!(m => CalcMeasureRecord(m.column, enumName(m.aggregation), m.label,
            m.description)).array, v.filter, v.createdAt, v.createdBy, v.updatedAt);
}

CalculationView toDomain(CalcViewRecord r) {
    CalculationView v;
    v.name = r.name;
    v.label = r.label;
    v.description = r.description;
    v.viewType = parseEnum!CalcViewType(r.viewType.length ? r.viewType : "cube");
    v.baseTable = r.baseTable;
    v.baseAlias = r.baseAlias;
    foreach (j; r.joins)
        v.joins ~= CalcJoin(j.table, j.alias_, j.left, j.leftColumn, j.rightColumn);
    foreach (a; r.attributes)
        v.attributes ~= CalcAttribute(a.column, a.label, a.description);
    foreach (m; r.measures)
        v.measures ~= CalcMeasure(m.column, parseEnum!Aggregation(m.aggregation.length ? m.aggregation : "sum"),
            m.label, m.description);
    v.filter = r.filter;
    v.createdAt = r.createdAt;
    v.createdBy = r.createdBy;
    v.updatedAt = r.updatedAt;
    return v;
}

TenantStateRecord toRecord(TenantCloudState s) {
    return TenantStateRecord(s.workloadClasses, s.workloadMappings, s.views.map!(v => toRecord(v)).array, s.bindings,
        s.products, s.trace);
}

TenantCloudState toDomain(TenantStateRecord r) {
    return TenantCloudState(r.workloadClasses, r.workloadMappings, r.views.map!(v => toDomain(v)).array, r.bindings,
        r.products, r.trace);
}

/// Ganzer Zustand als JSON.
Json cloudStateToJson(DatabaseInstance[] instances, TenantCloudState[string] tenants) {
    CloudStateRecord r;
    r.instances = instances.map!(i => toRecord(i)).array;
    foreach (name, s; tenants)
        r.tenants[name] = toRecord(s);
    return serializeToJson(r);
}

void cloudStateFromJson(Json json, out DatabaseInstance[] instances, out TenantCloudState[string] tenants) {
    if (json.type != Json.Type.object)
        return;
    auto r = deserializeJson!CloudStateRecord(json);
    instances = r.instances.map!(i => toDomain(i)).array;
    foreach (name, s; r.tenants)
        tenants[name] = toDomain(s);
}

unittest {
    auto i = DatabaseInstance("acme", "Test");
    i.performanceClass = PerformanceClass.highMemory;
    CalculationView v;
    v.name = "V";
    v.baseTable = "t";
    v.measures = [CalcMeasure("x", Aggregation.countDistinct)];
    TenantCloudState s;
    s.views = [v];
    s.workloadClasses = [WorkloadClass("ETL", 7)];
    auto json = cloudStateToJson([i], ["acme": s]);
    assert(json["instances"][0]["performanceClass"].get!string == "highMemory");
    assert(json["tenants"]["acme"]["views"][0]["measures"][0]["aggregation"].get!string == "countDistinct");
    DatabaseInstance[] back;
    TenantCloudState[string] tenants;
    cloudStateFromJson(json, back, tenants);
    assert(back[0].performanceClass == PerformanceClass.highMemory && back[0].vcpus == 1);
    assert(tenants["acme"].views[0].measures[0].aggregation == Aggregation.countDistinct);
    assert(tenants["acme"].workloadClasses[0].priority == 7);
    // ältere oder handgeschriebene Dateien ohne die meisten Felder
    cloudStateFromJson(Json(["instances": Json([Json(["name": Json("x")])])]), back, tenants);
    assert(back[0].memoryGb == 32 && back[0].performanceClass == PerformanceClass.memory);
}
