/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Application-wide services: default implementations of the clock and the
/// id generator, plus a fixed clock / sequential ids for tests.
module neko.platform.application.services.fixedclock;

import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.uuid : randomUUID;
import neko.platform.ports.services;

@safe:

/// Deterministic clock for tests.
class FixedClock : IClock {
  SysTime time;

  this(SysTime time) {
    this.time = time;
  }

  SysTime now() {
    return time;
  }
}

