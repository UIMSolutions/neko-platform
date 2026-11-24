/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Service assignments: which services (`serviceCatalogue`) each subaccount
/// of the global account may use, seen from the global account.
///
/// A subaccount whose service list is empty has every service, including
/// services added later; assigning the last missing service returns it to
/// that state. Unassigning from such a subaccount lists every other service
/// explicitly. A subaccount keeps at least one service, and a service stays
/// assigned while a role collection of the subaccount grants its rights.
///
/// Entitlements belong to the service whose key prefixes the plan key
/// ("files.storage" → "files"); plans of other services (platform, network,
/// support) are shown on their own.
module neko.platform.domain.entities.serviceassignments;

import std.algorithm : any, canFind, map, sort, uniq;
import std.array : array;
import std.string : strip, toLower;
import neko.platform.domain.entities.landscape : Entitlement, Landscape, ServiceInfo, Subaccount, serviceCatalogue,
  serviceOfRight;
import neko.platform.domain.exceptions;

@safe:

/// One service for one subaccount.
struct ServiceAssignment {
  string subaccount;
  string service;
  /// The subaccount's role collections may grant the service's rights.
  bool assigned;
  /// Listed explicitly; false = the subaccount has every service.
  bool explicit;
  /// Role collections of the subaccount that grant rights of the service
  /// (it cannot be unassigned while there are any).
  string[] usedBy;
  /// The subaccount's entitlements to plans of this service.
  Entitlement[] entitlements;
}

/// A service with its assignment to every subaccount (in subaccount order).
struct ServiceRow {
  ServiceInfo service;
  ServiceAssignment[] cells;
  size_t assigned;
}

/// Keys of every service.
string[] serviceKeys() pure {
  return serviceCatalogue().map!(s => s.key).array.sort.array;
}

/// The services `s` has, explicitly or because it has all.
string[] effectiveServices(const Subaccount s) pure {
  return s.services.length ? s.services.dup.sort.array : serviceKeys();
}

/// The service list after (un)assigning `service`: sorted, [] when it
/// covers every service. Throws for an unknown service or when the last
/// service would go.
string[] withService(const(string)[] current, string service, bool assign) pure {
  auto key = service.strip.toLower;
  auto all = serviceKeys();
  if (!all.canFind(key))
    throw new ValidationException("Unknown service '" ~ service.strip ~ "'");
  string[] effective = current.length ? current.dup : all.dup;
  if (assign)
    effective ~= key;
  else {
    string[] rest;
    foreach (k; effective)
      if (k != key)
        rest ~= k;
    effective = rest;
  }
  effective = effective.sort.uniq.array;
  if (effective.length == 0)
    throw new ValidationException("A subaccount needs at least one service");
  return effective == all ? null : effective;
}

/// Role collections of `s` granting rights of `service`.
string[] collectionsUsing(const Subaccount s, string service) pure {
  string[] names;
  foreach (rc; s.roleCollections)
    if (rc.rights.any!(r => serviceOfRight(r) == service))
      names ~= rc.name;
  return names;
}

/// Every service × every subaccount.
ServiceRow[] serviceMatrix(const Landscape l) pure {
  ServiceRow[] rows;
  foreach (svc; serviceCatalogue()) {
    ServiceRow row;
    row.service = svc;
    foreach (s; l.subaccounts) {
      ServiceAssignment a;
      a.subaccount = s.key;
      a.service = svc.key;
      a.explicit = s.services.length > 0;
      a.assigned = s.allowsService(svc.key);
      a.usedBy = collectionsUsing(s, svc.key);
      foreach (e; s.entitlements)
        if (serviceOfRight(e.plan) == svc.key)
          a.entitlements ~= e;
      if (a.assigned)
        row.assigned++;
      row.cells ~= a;
    }
    rows ~= row;
  }
  return rows;
}

/// Plans whose service has no access rights (platform, network, support, …).
string[] plansWithoutService(const Landscape l) pure {
  auto keys = serviceKeys();
  string[] list;
  foreach (p; l.plans)
    if (!keys.canFind(serviceOfRight(p.key)))
      list ~= p.key;
  return list;
}

///
unittest {
  import std.datetime.systime : SysTime;
  import neko.platform.domain.entities.landscape : RoleCollection, defaultPlans;

  auto all = serviceKeys();
  assert(all.canFind("files") && all.canFind("landscape") && !all.canFind("sites"));
  // from "every service": unassigning lists the others
  auto noFiles = withService(null, "Files", false);
  assert(noFiles.length == all.length - 1 && !noFiles.canFind("files"));
  // assigning the last missing one returns to "every service"
  assert(withService(noFiles, "files", true) is null);
  assert(withService(["files"], "users", true) == ["files", "users"]);
  bool failed(void delegate() @safe f) {
    try
      f();
    catch (ValidationException)
      return true;
    return false;
  }

  assert(failed(() { withService(["files"], "files", false); }));
  assert(failed(() { withService(null, "sites", true); }));

  Landscape l;
  l.plans = defaultPlans();
  Subaccount a, b;
  a.key = "a";
  b.key = "b";
  b.services = ["files"];
  b.roleCollections = [RoleCollection("Editors", "", ["files.manage"], ["bob"])];
  b.entitlements = [Entitlement("files.storage", 5), Entitlement("platform.requests", -1)];
  l.subaccounts = [a, b];
  auto m = serviceMatrix(l);
  foreach (row; m) {
    assert(row.cells.length == 2 && row.cells[0].assigned && !row.cells[0].explicit);
    if (row.service.key == "files") {
      assert(row.assigned == 2 && row.cells[1].usedBy == ["Editors"]);
      assert(row.cells[1].entitlements == [Entitlement("files.storage", 5)]);
    } else
      assert(row.assigned == 1 && !row.cells[1].assigned);
  }
  assert(plansWithoutService(l) == ["platform.requests", "network.egress", "support.premium"]);
}
