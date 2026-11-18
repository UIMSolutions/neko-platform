/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Technische Ablagen: Dateien für Mandanten, Benutzer, Rollen, Protokolle und das Anweisungsprotokoll.
module neko.database.persistence.storages;

public:
    import neko.database.persistence.storages.log_store;
    import neko.database.persistence.storages.statement_log;
    import neko.database.persistence.storages.tenant_storage;
    import neko.database.persistence.storages.tenant_store;
    import neko.database.persistence.storages.user_store;
