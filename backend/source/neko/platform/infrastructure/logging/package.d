/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Technical logging and the log-based event publisher (audit trail).
module neko.platform.infrastructure.logging;

import vibe.core.log;
import neko.platform.ports.messaging;

@safe:

/// Map a configured level name to vibe.d; unknown names fall back to info.
void configureLogging(string level) {
  LogLevel l;
  switch (level) {
  case "trace":
    l = LogLevel.trace;
    break;
  case "debug":
    l = LogLevel.debug_;
    break;
  case "warn":
    l = LogLevel.warn;
    break;
  case "error":
    l = LogLevel.error;
    break;
  default:
    l = LogLevel.info;
  }
  setLogLevel(l);
}

/// Writes every domain event to the log and keeps the latest ones in memory
/// for the status page. Replace with a broker adapter for an event mesh.
class LoggingEventPublisher : IEventPublisher {
  private PlatformEvent[] buffer;
  private size_t capacity;

  this(size_t capacity = 100) {
    this.capacity = capacity;
  }

  void publish(PlatformEvent event) {
    logInfo("[event] %s %s by %s: %s", event.type, event.subject, event.actor, event.message);
    buffer ~= event;
    if (buffer.length > capacity)
      buffer = buffer[$ - capacity .. $];
  }

  /// Newest first.
  PlatformEvent[] recent() {
    PlatformEvent[] result;
    foreach_reverse (e; buffer)
      result ~= e;
    return result;
  }
}

///
unittest {
  auto p = new LoggingEventPublisher(2);
  foreach (i; 0 .. 3)
    p.publish(PlatformEvent("t", [cast(char)('a' + i)].idup));
  assert(p.recent.length == 2 && p.recent[0].subject == "c");
}
