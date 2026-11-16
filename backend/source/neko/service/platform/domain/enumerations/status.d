/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Life-cycle and health states of platform services and transfer packages.
module neko.service.platform.domain.enumerations.status;

import std.conv : to;
import std.traits : EnumMembers;

@safe:

/// Life cycle of a registered service.
///
///   registered ──activate──▶ active ──suspend──▶ suspended
///        │                     ▲                   │
///        │                     └─────activate──────┘
///        └──────────────── retire (from any state) ──▶ retired (final)
enum ServiceStatus {
  registered,
  active,
  suspended,
  retired
}

/// Result of the last health probe of a service.
enum HealthState {
  unknown,
  up,
  down
}

/// Direction of a transfer package as seen from this platform instance.
enum TransferDirection {
  outbound,
  inbound
}

/// Outcome of a transfer.
enum TransferStatus {
  exported,
  imported,
  rejected
}

/// Parse an enum value by its member name (case-sensitive, as serialized).
bool tryParseEnum(E)(string text, out E value) if (is(E == enum)) {
  static foreach (member; EnumMembers!E) {
    if (text == member.to!string) {
      value = member;
      return true;
    }
  }
  return false;
}

///
unittest {
  ServiceStatus s;
  assert(tryParseEnum("suspended", s) && s == ServiceStatus.suspended);
  assert(!tryParseEnum("deleted", s));
}
