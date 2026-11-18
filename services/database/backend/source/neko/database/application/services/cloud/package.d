/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Anwendungsdienste der Cloud-Funktionen (HANA-Cloud-ähnlich): Instanzen, Workloads, Überwachung, Advisor,
/// Calculation Views, Bindungen, Datenprodukte und Assistent.
module neko.database.application.services.cloud;

public:
    import neko.database.application.services.cloud.analytics;
    import neko.database.application.services.cloud.assistant;
    import neko.database.application.services.cloud.common;
    import neko.database.application.services.cloud.instances;
    import neko.database.application.services.cloud.integration;
    import neko.database.application.services.cloud.monitoring;
    import neko.database.application.services.cloud.workloads;
    import neko.database.application.services.cloud.composition;
