/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports für Ereignisse. Die Ereignis- und Audit-Ports liegen in neko.database.ports.ports (IEventLog,
/// IAuditTrail); dieses Paket bündelt sie für Adapter, die nur Nachrichten brauchen.
module neko.database.ports.messaging;

public import neko.database.ports.ports : IAuditTrail, IEventLog, AuditRecord;
