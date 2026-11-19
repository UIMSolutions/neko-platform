/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Generic accessor over the aggregates: the display name.
module neko.directory.domain.services.scoping;

import neko.directory;

mixin(ShowModule!());

@safe:

/// The display name of an aggregate: user name, name, display name or description.
string nameOf(TEntity)(const TEntity entity) {
  static if (__traits(hasMember, TEntity, "userName"))
    return entity.userName;
  else static if (__traits(hasMember, TEntity, "name"))
    return entity.name;
  else static if (__traits(hasMember, TEntity, "displayName"))
    return entity.displayName;
  else static if (__traits(hasMember, TEntity, "description"))
    return entity.description;
  else
    return entity.id.value;
}

///
unittest {
  auto u = DirectoryUser(TenantId("t1"));
  u.userName = "jane";
  auto g = DirectoryGroup(TenantId("t1"));
  g.displayName = "Sales";
  auto p = PasswordPolicy(TenantId("t1"));
  p.name = "Standard";
  assert(nameOf(u) == "jane" && nameOf(g) == "Sales" && nameOf(p) == "Standard");
}
