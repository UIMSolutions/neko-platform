/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ports for application-wide services (time, identifiers). Use cases depend
/// on these abstractions so tests can supply deterministic implementations.
module neko.platform.ports.services.clock;

import std.datetime.systime : SysTime;

@safe:

interface IClock {
  SysTime now();
}

