/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The global accounts of a platform instance (one security domain).
///
/// Global accounts are physically separate: each has its own data directory
/// with its own document store, file store, user accounts, roles, sessions,
/// landscape (directories, subaccounts, tenants, spaces) and usage. Nothing
/// is shared between them but the process, the network security (firewall,
/// IP lists) and the logs of the instance.
///
/// A request belongs to the global account whose host names match its host
/// (exactly, or as a parent domain: "acme.example" also takes
/// "shop.acme.example"; the longest match wins), else to the one named in the
/// X-Neko-Global-Account header, else to the default global account.
module neko.platform.domain.entities.globalaccounts;

import std.algorithm : any, canFind, count, endsWith, sort, uniq;
import std.array : array;
import std.datetime.systime : SysTime;
import std.string : strip, toLower;
import neko.platform.domain.entities.landscape : landscapeKey;
import neko.platform.domain.entities.site : normalizeHost, validHost;
import neko.platform.domain.exceptions;

@safe:

/// Where the global accounts other than the default one keep their data,
/// below the data directory of the instance.
enum globalAccountsDir = "global-accounts";

struct GlobalAccountEntry {
  /// 2–40 characters a-z, 0-9, '-', '.' (landscapeKey).
  string key;
  string name;
  /// Host names that select it (lower case, without port).
  string[] hosts;
  /// Its data directory relative to the instance's data directory; "" = the
  /// instance's data directory itself (the default global account, which
  /// keeps the layout of single-account instances).
  string dataDir;
  /// Answers requests no other global account claims; there is exactly one.
  bool isDefault;
  string description;
  SysTime createdAt;
  SysTime modifiedAt;

  GlobalAccountEntry copy() const pure nothrow {
    return GlobalAccountEntry(key, name, hosts.dup, dataDir, isDefault, description, createdAt, modifiedAt);
  }

  /// Whether this account claims `host`, and how specifically (0 = not).
  size_t matches(string host) const pure nothrow {
    size_t best;
    foreach (h; hosts)
      if ((host == h || host.endsWith("." ~ h)) && h.length > best)
        best = h.length;
    return best;
  }
}

/// The data directory a new global account gets.
string dataDirFor(string key) pure {
  return globalAccountsDir ~ "/" ~ key;
}

/// Normalizes and checks the fields a user can set.
GlobalAccountEntry validEntry(GlobalAccountEntry e) {
  e.key = landscapeKey(e.key, "Global account");
  e.name = e.name.strip;
  if (e.name.length == 0)
    e.name = e.key;
  if (e.name.length > 128)
    throw new ValidationException("The name of a global account must have at most 128 characters");
  string[] list;
  foreach (h; e.hosts)
    if (h.strip.length)
      list ~= validHost(h);
  e.hosts = list.sort.uniq.array;
  e.description = e.description.strip;
  return e;
}

/// Rule violations of a set of global accounts (empty = fine).
string[] validateAccounts(const(GlobalAccountEntry)[] accounts) pure {
  string[] problems;
  if (accounts.length && accounts.count!(a => a.isDefault) != 1)
    problems ~= "Exactly one global account must be the default";
  foreach (i, a; accounts)
    foreach (b; accounts[0 .. i]) {
      if (a.key == b.key)
        problems ~= "The key '" ~ a.key ~ "' is used twice";
      if (a.dataDir == b.dataDir)
        problems ~= "The global accounts " ~ b.key ~ " and " ~ a.key ~ " share the data directory '" ~ a.dataDir
          ~ "'; global accounts are physically separate";
      foreach (h; a.hosts)
        if (b.hosts.canFind(h))
          problems ~= "The host name " ~ h ~ " is claimed by " ~ b.key ~ " and " ~ a.key;
    }
  return problems;
}

/// The global account of a request (see the module documentation). `accounts`
/// must not be empty.
GlobalAccountEntry resolveAccount(const(GlobalAccountEntry)[] accounts, string host, string header) pure {
  size_t best;
  ptrdiff_t found = -1;
  auto h = normalizeHost(host);
  foreach (i, a; accounts) {
    auto m = a.matches(h);
    if (m > best) {
      best = m;
      found = i;
    }
  }
  if (found < 0 && header.strip.length) {
    auto k = header.strip.toLower;
    foreach (i, a; accounts)
      if (a.key == k)
        found = i;
    if (found < 0)
      throw new NotFoundException("Global account", k);
  }
  if (found < 0)
    foreach (i, a; accounts)
      if (a.isDefault)
        found = i;
  if (found < 0)
    throw new NotFoundException("Global account", "(default)");
  return accounts[found].copy;
}

///
unittest {
  auto def = GlobalAccountEntry("platform", "Platform", null, "", true);
  auto acme = validEntry(GlobalAccountEntry(" ACME ", "", ["ACME.example:8080", "acme.example", "shop.acme.example"],
    dataDirFor("acme")));
  assert(acme.key == "acme" && acme.name == "acme" && acme.hosts == ["acme.example", "shop.acme.example"]);
  auto beta = GlobalAccountEntry("beta", "Beta", ["beta.example"], dataDirFor("beta"));
  auto list = [def, acme, beta];
  assert(validateAccounts(list).length == 0);
  assert(resolveAccount(list, "eu.shop.acme.example", "").key == "acme");
  assert(resolveAccount(list, "beta.example", "acme").key == "beta"); // the host wins over the header
  assert(resolveAccount(list, "localhost", "beta").key == "beta");
  assert(resolveAccount(list, "localhost", "").key == "platform");
  assert(resolveAccount(list, "notacme.example", "").key == "platform");
  bool missing;
  try
    resolveAccount(list, "localhost", "nope");
  catch (NotFoundException)
    missing = true;
  assert(missing);

  auto clash = beta;
  clash.key = "gamma";
  assert(validateAccounts([def, beta, clash]).length == 2); // host and data directory
  def.isDefault = false;
  assert(validateAccounts([def, beta]).length == 1);
}
