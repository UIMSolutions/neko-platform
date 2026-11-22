/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Application-wide services: default implementations of the clock and the
/// id generator, plus a fixed clock / sequential ids for tests.
module neko.platform.application.services.sequentialids;

import std.conv : to;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.uuid : randomUUID;
import neko.platform.ports.services;

@safe:

/// "prefix-1", "prefix-2", … for tests.
class SequentialIds : IIdGenerator {
  private string prefix;
  private size_t counter;

  this(string prefix = "id") {
    this.prefix = prefix;
  }

  string newId() {
    return prefix ~ "-" ~ (++counter).to!string;
  }
}
