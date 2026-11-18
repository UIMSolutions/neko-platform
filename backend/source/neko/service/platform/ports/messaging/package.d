/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven port for domain events (audit trail, event broker integration).
module neko.platform.ports.messaging;

import std.datetime.systime : SysTime;

@safe:

struct PlatformEvent {
  /// e.g. "service.registered", "transfer.rejected"
  string type;
  /// Id of the affected service or transfer.
  string subject;
  string actor;
  string message;
  SysTime at;
}

interface IEventPublisher {
  void publish(PlatformEvent event);
}
