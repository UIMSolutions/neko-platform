/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for external systems: the registered services themselves.
module neko.platform.ports.gateways.servicehealth;

import neko.platform.domain.enumerations : HealthState;

@safe:

interface IServiceHealthGateway {
  /// Probe a health URL; never throws (unreachable → HealthState.down).
  HealthState probe(string url);
}
