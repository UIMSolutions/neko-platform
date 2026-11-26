/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Service catalogue: register, change, run through the life cycle, remove.
module neko.platform.application.usecases.manage.services;

import std.algorithm : canFind, filter, map, sort;
import std.array : array;
import std.conv : to;
import std.string : toLower;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.ports;

@safe:

class ManageServicesUseCase : IManageServicesUseCase {
  private IServiceRepository services;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  private ClassificationPolicy hosting;

  this(IServiceRepository services, IEventPublisher events, IClock clock, IIdGenerator ids,
      SecurityDomain platformDomain) {
    this.services = services;
    this.events = events;
    this.clock = clock;
    this.ids = ids;
    this.hosting = ClassificationPolicy(platformDomain);
  }

  ServiceDto[] list(ServiceQuery query) {
    auto search = query.search.toLower;
    auto result = services.all
      .filter!(s => query.status.length == 0 || s.status.to!string == query.status)
      .filter!(s => query.classification.length == 0 || s.classification.label == query.classification)
      .filter!(s => search.length == 0 || s.name.value.canFind(search) || s.description.toLower.canFind(search))
      .array;
    result.sort!((a, b) => a.name.value < b.name.value);
    return result.map!(s => s.toDto).array;
  }

  ServiceDto get(string id) {
    return load(id).toDto;
  }

  ServiceDto register(RegisterServiceRequest request, string actor) {
    auto name = ServiceName(request.name);
    PlatformService existing;
    if (services.tryGetByName(name.value, existing))
      throw new ConflictException("A service named '" ~ name.value ~ "' is already registered");

    SecurityDomain classification = hosting.platformDomain;
    if (request.classification.length > 0 && !tryParseSecurityDomain(request.classification, classification))
      throw new ValidationException("Unknown classification '" ~ request.classification ~ "'");
    hosting.requireHostable(classification);

    auto now = clock.now;
    PlatformService service;
    service.id = ServiceId(ids.newId);
    service.name = name;
    service.description = request.description;
    service.classification = classification;
    service.endpoint = ServiceEndpoint(request.baseUrl, request.healthPath);
    service.createdAt = now;
    service.modifiedAt = now;
    if (request.activate)
      service.activate(now);

    services.save(service);
    emit("service.registered", service, actor, "Registered " ~ classification.label ~ " service " ~ name.value);
    return service.toDto;
  }

  ServiceDto update(string id, UpdateServiceRequest request, string actor) {
    auto service = load(id);
    auto description = request.description.isNull ? service.description : request.description.get;
    auto endpoint = ServiceEndpoint(
      request.baseUrl.isNull ? service.endpoint.baseUrl : request.baseUrl.get,
      request.healthPath.isNull ? service.endpoint.healthPath : request.healthPath.get);
    service.changeDetails(description, endpoint, clock.now);
    services.save(service);
    emit("service.changed", service, actor, "Changed service " ~ service.name.value);
    return service.toDto;
  }

  ServiceDto activate(string id, string actor) {
    auto service = load(id);
    service.activate(clock.now);
    return persist(service, "service.activated", actor);
  }

  ServiceDto suspend(string id, string actor) {
    auto service = load(id);
    service.suspend(clock.now);
    return persist(service, "service.suspended", actor);
  }

  ServiceDto retire(string id, string actor) {
    auto service = load(id);
    service.retire(clock.now);
    return persist(service, "service.retired", actor);
  }

  void remove(string id, string actor) {
    auto service = load(id);
    if (!service.isRetired)
      throw new InvalidStateTransitionException("Retire service '" ~ service.name.value ~ "' before removing it");
    services.remove(service.id);
    emit("service.removed", service, actor, "Removed service " ~ service.name.value);
  }

  private PlatformService load(string id) {
    PlatformService service;
    if (!services.tryGet(ServiceId(id), service))
      throw new NotFoundException("Service", id);
    return service;
  }

  private ServiceDto persist(PlatformService service, string eventType, string actor) {
    services.save(service);
    emit(eventType, service, actor, service.name.value ~ " is now " ~ service.status.to!string);
    return service.toDto;
  }

  private void emit(string type, const PlatformService service, string actor, string message) {
    events.publish(PlatformEvent(type, service.id.value, actor, message, clock.now));
  }
}

version (unittest) {
  import neko.platform.application.services : FixedClock, SequentialIds;
  import std.datetime.systime : SysTime;

  /// In-memory test doubles (the real adapters live in persistence/).
  class FakeServices : IServiceRepository {
    PlatformService[string] items;

    PlatformService[] all() {
      return items.values;
    }

    bool tryGet(ServiceId id, out PlatformService s) {
      if (auto p = id.value in items) {
        s = *p;
        return true;
      }
      return false;
    }

    bool tryGetByName(string name, out PlatformService s) {
      foreach (item; items)
        if (item.name.value == name) {
          s = item;
          return true;
        }
      return false;
    }

    void save(PlatformService s) {
      items[s.id.value] = s;
    }

    bool remove(ServiceId id) {
      return items.remove(id.value);
    }
  }

  class RecordingEvents : IEventPublisher {
    PlatformEvent[] published;

    void publish(PlatformEvent e) {
      published ~= e;
    }
  }
}

///
unittest {
  auto repo = new FakeServices;
  auto events = new RecordingEvents;
  auto uc = new ManageServicesUseCase(repo, events, new FixedClock(SysTime(0)), new SequentialIds("svc"),
    SecurityDomain.restricted);

  auto created = uc.register(RegisterServiceRequest("management", "Accounts", "open", "http://localhost:8098", "", true), "jane");
  assert(created.id == "svc-1" && created.status == "active" && created.classification == "open");

  // hosting rule
  bool refused;
  try
    uc.register(RegisterServiceRequest("vault", "", "secret"), "jane");
  catch (PolicyViolationException)
    refused = true;
  assert(refused);

  // unique names
  bool conflict;
  try
    uc.register(RegisterServiceRequest("management"), "jane");
  catch (ConflictException)
    conflict = true;
  assert(conflict);

  assert(uc.list(ServiceQuery("acc")).length == 1);
  assert(uc.list(ServiceQuery("", "suspended")).length == 0);

  uc.suspend("svc-1", "jane");
  bool mustRetire;
  try
    uc.remove("svc-1", "jane");
  catch (InvalidStateTransitionException)
    mustRetire = true;
  assert(mustRetire);

  uc.retire("svc-1", "jane");
  uc.remove("svc-1", "jane");
  assert(repo.items.length == 0);
  assert(events.published.length == 4);
  assert(events.published[$ - 1].type == "service.removed");
}
