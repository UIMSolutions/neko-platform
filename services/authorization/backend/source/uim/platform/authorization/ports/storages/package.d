/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven port for low-level data stores: the document store of
/// neko-services-platform:service (collection → tenant → key → JSON document).
/// Implementations: memory, JSON file (neko-services-platform:service), MongoDB (persistence.storages).
module neko.service.authorization.ports.storages;

public import uim.platform.service.ports.storages.documents : IDocumentStore;
