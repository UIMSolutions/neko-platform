/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Probe the health endpoints of active services.
module neko.service.platform.application.usecases.check_service_health;

import std.conv : to;
import neko.service.platform.domain;
import neko.service.platform.application.dtos;
import neko.service.platform.ports;

@safe:

class CheckServiceHealthUseCase : ICheckServiceHealthUseCase {
  private IServiceRepository services;
  private IServiceHealthGateway gateway;
  private IEventPublisher events;
  private IClock clock;

  this(IServiceRepository services, IServiceHealthGateway gateway, IEventPublisher events, IClock clock) {
    this.services = services;
    this.gateway = gateway;
    this.events = events;
    this.clock = clock;
  }

  ServiceDto check(string id) {
    PlatformService service;
    if (!services.tryGet(ServiceId(id), service))
      throw new NotFoundException("Service", id);
    if (!service.isMonitored)
      throw new InvalidStateTransitionException("Service '" ~ service.name.value
          ~ "' is not monitored (it must be active and have a base URL)");
    probe(service);
    return service.toDto;
  }

  size_t checkAll() {
    size_t checked;
    foreach (service; services.all) {
      if (!service.isMonitored)
        continue;
      probe(service);
      checked++;
    }
    return checked;
  }

  private void probe(ref PlatformService service) {
    auto previous = service.health;
    service.recordHealth(gateway.probe(service.endpoint.healthUrl), clock.now);
    services.save(service);
    if (service.health != previous)
      events.publish(PlatformEvent("service.health", service.id.value, "system",
          service.name.value ~ " is " ~ service.health.to!string, clock.now));
  }
}

///
unittest {
  import std.datetime.systime : SysTime;
  import neko.service.platform.application.services : FixedClock;
  import neko.service.platform.application.usecases.manage_services : FakeServices, RecordingEvents;

  class DownGateway : IServiceHealthGateway {
    HealthState probe(string url) {
      return HealthState.down;
    }
  }

  auto repo = new FakeServices;
  PlatformService s;
  s.id = ServiceId("a");
  s.name = ServiceName("alpha");
  s.endpoint = ServiceEndpoint("http://127.0.0.1:1", "");
  s.status = ServiceStatus.active;
  repo.save(s);
  s.id = ServiceId("b");
  s.name = ServiceName("beta");
  s.status = ServiceStatus.suspended;
  repo.save(s);

  auto events = new RecordingEvents;
  auto uc = new CheckServiceHealthUseCase(repo, new DownGateway, events, new FixedClock(SysTime(1)));
  assert(uc.checkAll == 1);
  assert(repo.items["a"].health == HealthState.down);
  assert(events.published.length == 1);
  assert(uc.check("a").health == "down");
  assert(events.published.length == 1); // unchanged → no new event
}
