/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The global accounts of the instance (see domain.entities.globalaccounts).
module neko.platform.application.usecases.manage_globalaccounts;

import core.time : seconds;
import std.algorithm : countUntil, filter;
import std.array : array, join;
import std.datetime.systime : SysTime;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.ports;

@safe:

class ManageGlobalAccountsUseCase : IManageGlobalAccountsUseCase {
  private IGlobalAccountRepository repo;
  private IEventPublisher events;
  private IClock clock;
  // Requests resolve their global account on every call: a copy, refreshed
  // after changes here and at least every 10 seconds (changes by the CLI).
  private GlobalAccountEntry[] cached;
  private SysTime cachedAt;

  this(IGlobalAccountRepository repo, IEventPublisher events, IClock clock) {
    this.repo = repo;
    this.events = events;
    this.clock = clock;
  }

  GlobalAccountEntry[] list() {
    return repo.all();
  }

  GlobalAccountEntry get(string key) {
    GlobalAccountEntry e;
    if (!repo.tryGet(key, e))
      throw new NotFoundException("Global account", key);
    return e;
  }

  GlobalAccountEntry create(GlobalAccountEntryRequest r, string actor) {
    auto e = validEntry(GlobalAccountEntry(r.key, r.name, r.hosts.dup, "", false, r.description));
    GlobalAccountEntry existing;
    if (repo.tryGet(e.key, existing))
      throw new ConflictException("A global account '" ~ e.key ~ "' already exists");
    e.dataDir = dataDirFor(e.key);
    e.createdAt = e.modifiedAt = clock.now;
    check(repo.all() ~ e);
    repo.save(e);
    emit("globalaccount.created", e.key, actor, "Created global account " ~ e.key ~ " (data in " ~ e.dataDir ~ ")");
    return e;
  }

  GlobalAccountEntry update(string key, GlobalAccountEntryRequest r, string actor) {
    auto e = get(key);
    auto v = validEntry(GlobalAccountEntry(e.key, r.name, r.hosts.dup, e.dataDir, e.isDefault, r.description));
    e.name = v.name;
    e.hosts = v.hosts;
    e.description = v.description;
    e.modifiedAt = clock.now;
    auto all = repo.all();
    all[all.countUntil!(x => x.key == e.key)] = e;
    check(all);
    repo.save(e);
    emit("globalaccount.changed", e.key, actor, "Changed global account " ~ e.key ~ " (hosts: "
        ~ (e.hosts.length ? e.hosts.join(", ") : "none") ~ ")");
    return e;
  }

  void remove(string key, string actor) {
    auto e = get(key);
    if (e.isDefault)
      throw new ConflictException("The default global account cannot be removed");
    repo.remove(e.key);
    emit("globalaccount.removed", e.key, actor, "Unregistered global account " ~ e.key ~ "; its data stays in "
        ~ e.dataDir);
  }

  GlobalAccountEntry resolve(string host, string header) {
    auto now = clock.now;
    if (cached.length == 0 || now - cachedAt > 10.seconds || now < cachedAt) {
      cached = repo.all();
      cachedAt = now;
    }
    try
      return resolveAccount(cached, host, header);
    catch (NotFoundException e) {
      // a global account named in the header may just have been created
      cached = repo.all();
      cachedAt = now;
      return resolveAccount(cached, host, header);
    }
  }

  GlobalAccountEntry ensureDefault(string key, string name) {
    foreach (e; repo.all())
      if (e.isDefault)
        return e;
    auto e = validEntry(GlobalAccountEntry(key, name, null, "", true));
    e.createdAt = e.modifiedAt = clock.now;
    repo.save(e);
    cached = null;
    return e;
  }

  private void check(const(GlobalAccountEntry)[] all) {
    auto problems = validateAccounts(all);
    if (problems.length)
      throw new ValidationException(problems.join("; "));
  }

  private void emit(string type, string subject, string actor, string message) {
    cached = null;
    events.publish(PlatformEvent(type, subject, actor, message, clock.now));
  }
}

///
unittest {
  import std.datetime.date : DateTime;
  import std.datetime.timezone : UTC;
  import neko.platform.application.services : FixedClock;
  import neko.platform.application.usecases.manage_users : fails, NoEvents;

  class FakeRegistry : IGlobalAccountRepository {
    GlobalAccountEntry[string] items;

    GlobalAccountEntry[] all() {
      import std.algorithm : sort;

      auto list = items.values;
      list.sort!((a, b) => a.isDefault != b.isDefault ? a.isDefault : a.key < b.key);
      return list;
    }

    bool tryGet(string key, out GlobalAccountEntry e) {
      if (auto p = key in items) {
        e = *p;
        return true;
      }
      return false;
    }

    void save(GlobalAccountEntry e) {
      items[e.key] = e;
    }

    bool remove(string key) {
      return items.remove(key);
    }
  }

  auto uc = new ManageGlobalAccountsUseCase(new FakeRegistry, new NoEvents,
    new FixedClock(SysTime(DateTime(2026, 11, 21, 8, 0, 0), UTC())));
  auto def = uc.ensureDefault("default", "Platform");
  assert(def.isDefault && def.dataDir == "" && uc.ensureDefault("x", "y").key == "default");

  auto acme = uc.create(GlobalAccountEntryRequest("acme", "ACME", ["acme.example"]), "op");
  assert(acme.dataDir == "global-accounts/acme" && !acme.isDefault);
  assert(fails!ConflictException(() { uc.create(GlobalAccountEntryRequest("acme"), "op"); }));
  assert(fails!ValidationException(() { uc.create(GlobalAccountEntryRequest("beta", "", ["acme.example"]), "op"); }));
  assert(uc.resolve("www.acme.example:8080", "").key == "acme" && uc.resolve("localhost", "").key == "default");
  assert(uc.resolve("localhost", "acme").key == "acme");

  uc.update("acme", GlobalAccountEntryRequest("", "ACME Corp", ["acme.example", "acme.test"]), "op");
  assert(uc.get("acme").name == "ACME Corp" && uc.resolve("acme.test", "").key == "acme");
  assert(fails!ConflictException(() { uc.remove("default", "op"); }));
  uc.remove("acme", "op");
  assert(uc.list().length == 1 && uc.resolve("acme.example", "").key == "default");
}
