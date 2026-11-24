/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Shared rule of the user and role use cases: nobody hands out rights they
/// do not hold themselves ("no privilege escalation").
module neko.platform.application.usecases.access;

import std.algorithm : filter, map;
import std.array : array, join;
import neko.platform.domain;
import neko.platform.ports;

@safe:

/// The effective rights of `actor`, if it names a user account. Actors that
/// are no account ("system", "cli:<user>") are trusted: whoever runs the CLI
/// already has the data directory.
bool tryActorRights(IUserRepository users, IRoleRepository roles, string actor, out AccessRight[] rights) {
  UserAccount account;
  try {
    if (!users.tryGetByName(UserName(actor).value, account))
      return false;
  } catch (ValidationException)
    return false; // "cli:jane" is not a valid user name
  rights = effectiveRights(account.roles, roles.all);
  return true;
}

/// Throws unless `actor` holds every right in `wanted`; `what` completes
/// "You cannot <what>".
void requireCovers(IUserRepository users, IRoleRepository roles, string actor, const(AccessRight)[] wanted,
    string what) {
  AccessRight[] held;
  if (!tryActorRights(users, roles, actor, held) || covers(held, wanted))
    return;
  auto missing = wanted.filter!(w => !covers(held, [w])).map!(w => w.key).array;
  throw new PolicyViolationException("You cannot " ~ what ~ ": it needs rights you do not hold ("
      ~ missing.join(", ") ~ ")");
}

// ── subaccount scope (file libraries) ────────────────────────────────────

/// Whether `actor` may reach the library of the subaccount `key`: global
/// account administrators, the subaccount's administrators and user group,
/// and actors that belong to no subaccount at all (operators, "system", the
/// CLI) — like accounts without limits before subaccounts scoped them.
bool mayAccessSubaccount(const Landscape l, string actor, string key) pure nothrow {
  if (l.isGlobalAdmin(actor))
    return true;
  Subaccount s;
  if (l.trySubaccount(key, s) && s.isUser(actor))
    return true;
  return l.subaccountsOf(actor).length == 0;
}

///
unittest {
  Landscape l;
  l.global.admins = ["root"];
  Subaccount a, b;
  a.key = "a";
  a.members = ["bob"];
  b.key = "b";
  b.admins = ["ann"];
  l.subaccounts = [a, b];
  assert(mayAccessSubaccount(l, "root", "a") && mayAccessSubaccount(l, "root", "b"));
  assert(mayAccessSubaccount(l, "bob", "a") && !mayAccessSubaccount(l, "bob", "b"));
  assert(mayAccessSubaccount(l, "ann", "b") && !mayAccessSubaccount(l, "ann", "a"));
  assert(mayAccessSubaccount(l, "system", "a") && mayAccessSubaccount(l, "eve", "b")); // in no subaccount
}
