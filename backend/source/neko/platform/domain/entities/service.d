/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A service registered in the platform catalogue of one security domain.
module neko.platform.domain.entities.service;

import std.conv : to;
import std.datetime.systime : SysTime;
import neko.platform.domain.enumerations;
import neko.platform.domain.exceptions;
import neko.platform.domain.types;

@safe:

struct PlatformService {
  ServiceId id;
  ServiceName name;
  string description;
  /// Classification of the data the service processes (≤ platform domain).
  SecurityDomain classification;
  ServiceEndpoint endpoint;
  ServiceStatus status = ServiceStatus.registered;
  HealthState health = HealthState.unknown;
  SysTime lastCheckedAt;
  SysTime createdAt;
  SysTime modifiedAt;

  bool isRetired() const pure nothrow {
    return status == ServiceStatus.retired;
  }

  /// Health is probed only for running services with an endpoint.
  bool isMonitored() const pure nothrow {
    return status == ServiceStatus.active && endpoint.isProbeable;
  }

  void activate(SysTime now) {
    requireNotRetired("activate");
    if (status == ServiceStatus.active)
      throw new InvalidStateTransitionException("Service '" ~ name.value ~ "' is already active");
    status = ServiceStatus.active;
    modifiedAt = now;
  }

  void suspend(SysTime now) {
    if (status != ServiceStatus.active)
      throw new InvalidStateTransitionException(
        "Only active services can be suspended ('" ~ name.value ~ "' is " ~ status.to!string ~ ")");
    status = ServiceStatus.suspended;
    health = HealthState.unknown;
    modifiedAt = now;
  }

  /// Final state: the entry is kept for audit purposes but can no longer change.
  void retire(SysTime now) {
    requireNotRetired("retire");
    status = ServiceStatus.retired;
    health = HealthState.unknown;
    modifiedAt = now;
  }

  void changeDetails(string description, ServiceEndpoint endpoint, SysTime now) {
    requireNotRetired("change");
    this.description = description;
    this.endpoint = endpoint;
    modifiedAt = now;
  }

  void recordHealth(HealthState state, SysTime now) pure nothrow {
    health = state;
    lastCheckedAt = now;
  }

  private void requireNotRetired(string action) const {
    if (isRetired)
      throw new InvalidStateTransitionException("Cannot " ~ action ~ " retired service '" ~ name.value ~ "'");
  }
}
///
unittest {
  import std.datetime.systime : Clock;

  auto now = Clock.currTime;
  PlatformService s;
  s.name = ServiceName("billing");
  s.endpoint = ServiceEndpoint("http://localhost:9000", "");

  s.activate(now);
  assert(s.status == ServiceStatus.active && s.isMonitored);
  s.suspend(now);
  assert(s.status == ServiceStatus.suspended && !s.isMonitored);
  s.activate(now);
  s.retire(now);

  bool rejected;
  try
    s.activate(now);
  catch (InvalidStateTransitionException)
    rejected = true;
  assert(rejected);
}
