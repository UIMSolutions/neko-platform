/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
///   
module neko.platform.infrastructure.logging.loggingeventpublisher;

import vibe.core.log;
import neko.platform.ports.messaging;

@safe:

/// Map a configured level name to vibe.d; unknown names fall back to info.
void configureLogging(string level) {
  import neko.platform.infrastructure.monitoring : parseLogLevel;

  setLogLevel(parseLogLevel(level));
}

/// Writes every domain event to the log and keeps the latest ones in memory
/// for the status page. Replace with a broker adapter for an event mesh.
class LoggingEventPublisher : IEventPublisher {
  private PlatformEvent[] buffer;
  private size_t capacity;
  private long[string] counts;

  this(size_t capacity = 100) {
    this.capacity = capacity;
  }

  void publish(PlatformEvent event) {
    logInfo("[event] %s %s by %s: %s", event.type, event.subject, event.actor, event.message);
    buffer ~= event;
    counts[event.type]++;
    if (buffer.length > capacity)
      buffer = buffer[$ - capacity .. $];
  }

  /// Events per type since the start.
  long[string] countsByType() {
    return counts.dup;
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
