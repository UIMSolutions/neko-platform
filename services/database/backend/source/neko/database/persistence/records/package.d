/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Technische Datensätze der Cloud-Ablage (hdb-cloud.json). Aufzählungen stehen als Namen darin, damit die Datei
/// lesbar bleibt und neue Werte alte Dateien nicht ungültig machen. Fehlende Felder bekommen Vorgaben (@optional).
module neko.database.persistence.records;

import neko.database.domain.entities.binding : ServiceBinding;
import neko.database.domain.entities.dataproduct : InstalledProduct;
import neko.database.domain.entities.workload : WorkloadClass, WorkloadMapping;
import neko.database.domain.types.monitoring : TraceSettings;
import vibe.data.serialization : optional;

@safe:

enum int cloudFormatVersion = 1;

struct InstanceRecord {
    string name;
    @optional string description;
    @optional string performanceClass = "memory";
    @optional size_t memoryGb = 32;
    @optional size_t storageGb = 120;
    @optional bool nseEnabled;
    @optional size_t ecnNodes;
    @optional string region;
    @optional string version_;
    @optional string createdAt, createdBy, updatedAt;
}

struct CalcJoinRecord {
    string table;
    @optional string alias_;
    @optional bool left;
    string leftColumn, rightColumn;
}

struct CalcAttributeRecord {
    string column;
    @optional string label, description;
}

struct CalcMeasureRecord {
    string column;
    @optional string aggregation = "sum";
    @optional string label, description;
}

struct CalcViewRecord {
    string name;
    @optional string label, description;
    @optional string viewType = "cube";
    string baseTable;
    @optional string baseAlias;
    @optional CalcJoinRecord[] joins;
    @optional CalcAttributeRecord[] attributes;
    @optional CalcMeasureRecord[] measures;
    @optional string filter;
    @optional string createdAt, createdBy, updatedAt;
}

struct TenantStateRecord {
    @optional WorkloadClass[] workloadClasses;
    @optional WorkloadMapping[] workloadMappings;
    @optional CalcViewRecord[] views;
    @optional ServiceBinding[] bindings;
    @optional InstalledProduct[] products;
    @optional TraceSettings trace;
}

struct CloudStateRecord {
    @optional int formatVersion = cloudFormatVersion;
    @optional InstanceRecord[] instances;
    @optional TenantStateRecord[string] tenants;
}
