/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ausgehende Ports (Driven) für Geschäftsdaten der Cloud-Funktionen.
module neko.database.ports.repositories;

import neko.database.domain;

@safe:

/// Einstellungen und Objekte eines Mandanten, die nicht in seinen Tabellen liegen.
struct TenantCloudState {
    WorkloadClass[] workloadClasses;
    WorkloadMapping[] workloadMappings;
    CalculationView[] views;
    ServiceBinding[] bindings;
    InstalledProduct[] products;
    TraceSettings trace;
}

/// Instanzen und Mandantenzustände. Lesen liefert Kopien; geschrieben wird immer der ganze Eintrag.
interface ICloudRepository {
    DatabaseInstance[] instances();
    bool hasInstance(string name);
    /// Wirft NotFound.
    DatabaseInstance instance(string name);
    void saveInstance(DatabaseInstance instance);
    void removeInstance(string name);

    TenantCloudState tenantState(string tenant);
    void saveTenantState(string tenant, TenantCloudState state);
    void removeTenantState(string tenant);
}
