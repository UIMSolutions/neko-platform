/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Data migrations, run at start-up on the raw documents (before the
/// repositories interpret them). Each one is idempotent.
module neko.platform.persistence.migrations;

import std.algorithm : canFind, filter, map, max, sort, startsWith;
import std.array : array;
import std.conv : to;
import vibe.data.json;
import neko.platform.persistence.records;
import neko.platform.ports.storages;

@safe:

/// Earlier versions had sites (tenants with host names, languages and a
/// home page) that ran in the spaces of subaccounts; files and usage belonged
/// to a site. Sites are gone, so their data moves to the subaccount that ran
/// the site (else to the first subaccount by key):
///
///   files      `site` → `subaccount`; the content moves from the blob folder
///              of the site to the folder of the subaccount
///   usage      "<month>|<site>" → "<month>|<subaccount>" (merged)
///   landscape  the "sites.site" plan and every entitlement to it, the
///              service "sites" and "sites.*" rights of role collections, the
///              site lists of subaccounts and spaces
///   sites      the collection is emptied
///
/// Needs at least one subaccount (run it after the landscape defaults);
/// without one it changes nothing. Returns what it did, for the log.
string[] migrateSites(IDocumentStore store, IBlobStore blobs) @trusted { // vibe.d iterates Json as @system
  string[] notes;
  auto subaccounts = store.load(subaccountsCollection);
  if (subaccounts.length == 0)
    return notes;
  auto keys = subaccounts.keys.sort.array;

  // site → subaccount, from the site lists still in the documents
  string[string] hostOf;
  foreach (key, doc; subaccounts) {
    foreach (site; strings(doc, "sites"))
      hostOf[site] = key;
    if (auto tenants = "tenants" in doc)
      if (tenants.type == Json.Type.array)
        foreach (t; *tenants)
          if (auto spaces = "spaces" in t)
            if (spaces.type == Json.Type.array)
              foreach (sp; *spaces)
                foreach (site; strings(sp, "sites"))
                  hostOf[site] = key;
  }
  string target(string site) {
    if (auto k = site in hostOf)
      return *k;
    return keys.canFind(site) ? site : keys[0];
  }

  // files
  auto files = store.load(filesCollection);
  size_t moved;
  foreach (id, ref doc; files) {
    auto sub = text(doc, "subaccount");
    auto site = text(doc, "site");
    if (sub.length && site.length == 0)
      continue;
    auto to = sub.length ? sub : target(site);
    if (site.length && site != to)
      moveBlob(blobs, site, to, id);
    doc["subaccount"] = to;
    if ("site" in doc)
      doc.remove("site");
    moved++;
  }
  if (moved) {
    store.store(filesCollection, files);
    notes ~= "moved " ~ moved.to!string ~ " file(s) from sites to subaccounts";
  }

  // usage
  auto usage = store.load(usageCollection);
  Json[string] merged;
  size_t rekeyed;
  foreach (key, doc; usage) {
    auto site = text(doc, "site");
    if (text(doc, "subaccount").length || site.length == 0) {
      merged[key] = doc;
      continue;
    }
    rekeyed++;
    auto sub = target(site);
    auto month = text(doc, "month");
    auto k = month ~ "|" ~ sub;
    auto u = UsageDocument(month, sub, number(doc, "requests"), number(doc, "bytesOut"),
      number(doc, "peakStorageBytes"));
    if (auto existing = k in merged) {
      u.requests += number(*existing, "requests");
      u.bytesOut += number(*existing, "bytesOut");
      u.peakStorageBytes += number(*existing, "peakStorageBytes"); // peaks of different sites add up
    }
    merged[k] = serializeToJson(u);
  }
  if (rekeyed) {
    store.store(usageCollection, merged);
    notes ~= "moved the usage of " ~ rekeyed.to!string ~ " site month(s) to subaccounts";
  }

  // landscape
  enum sitePlan = "sites.site";
  size_t cleaned;
  auto plans = store.load(plansCollection);
  string[] dropped;
  foreach (key, doc; plans)
    if (key == sitePlan || text(doc, "meter") == "sites")
      dropped ~= key;
  if (dropped.length) {
    foreach (k; dropped)
      plans.remove(k);
    store.store(plansCollection, plans);
    cleaned += dropped.length;
  }
  dropped ~= sitePlan;

  bool cleanNode(ref Json doc) {
    bool changed;
    if (auto e = "entitlements" in doc)
      if (e.type == Json.Type.array) {
        Json[] keep;
        foreach (x; *e)
          if (!dropped.canFind(text(x, "plan")))
            keep ~= x;
        if (keep.length != e.length) {
          doc["entitlements"] = Json(keep);
          changed = true;
        }
      }
    if (auto rcs = "roleCollections" in doc)
      if (rcs.type == Json.Type.array) {
        Json[] list;
        foreach (rc; *rcs) {
          auto rights = strings(rc, "rights");
          auto keep = rights.filter!(r => !r.startsWith("sites.")).array;
          if (keep.length != rights.length) {
            rc["rights"] = serializeToJson(keep);
            changed = true;
          }
          list ~= rc;
        }
        if (changed)
          doc["roleCollections"] = Json(list);
      }
    return changed;
  }

  auto global = store.load(landscapeCollection);
  if (auto g = "global" in global)
    if (cleanNode(*g)) {
      store.store(landscapeCollection, global);
      cleaned++;
    }
  auto directories = store.load(directoriesCollection);
  bool dirsChanged;
  foreach (key, ref doc; directories)
    dirsChanged |= cleanNode(doc);
  if (dirsChanged) {
    store.store(directoriesCollection, directories);
    cleaned++;
  }
  bool subsChanged;
  foreach (key, ref doc; subaccounts) {
    auto changed = cleanNode(doc);
    if ("sites" in doc) {
      doc.remove("sites");
      changed = true;
    }
    auto services = strings(doc, "services");
    if (services.canFind("sites")) {
      auto keep = services.filter!(s => s != "sites").array;
      // a subaccount that only had sites keeps its other services: every one
      doc["services"] = serializeToJson(keep);
      changed = true;
    }
    if (auto tenants = "tenants" in doc)
      if (tenants.type == Json.Type.array) {
        Json[] ts;
        foreach (t; *tenants) {
          if (auto spaces = "spaces" in t)
            if (spaces.type == Json.Type.array) {
              Json[] sps;
              foreach (sp; *spaces) {
                if ("sites" in sp) {
                  sp.remove("sites");
                  changed = true;
                }
                sps ~= sp;
              }
              t["spaces"] = Json(sps);
            }
          ts ~= t;
        }
        doc["tenants"] = Json(ts);
      }
    subsChanged |= changed;
  }
  if (subsChanged) {
    store.store(subaccountsCollection, subaccounts);
    cleaned++;
  }
  if (cleaned)
    notes ~= "removed the sites plan, service and rights from the landscape";

  auto sites = store.load(legacySitesCollection);
  if (sites.length) {
    store.store(legacySitesCollection, null);
    notes ~= "removed " ~ sites.length.to!string ~ " site(s) (" ~ sites.keys.sort.array.to!string ~ ")";
  }
  return notes;
}

private void moveBlob(IBlobStore blobs, string from, string to, string id) {
  try {
    auto path = blobs.localPath(from, id);
    if (path.length)
      blobs.putFile(to, id, path); // moves the file on the same volume
    else {
      auto data = blobs.get(from, id);
      if (data is null)
        return;
      blobs.put(to, id, data);
    }
    blobs.remove(from, id);
  } catch (Exception e) {
    // a name the blob store refuses, or content that is gone: the metadata
    // still moves, the download then reports the missing content
  }
}

private string text(const Json doc, string key) @trusted {
  if (doc.type != Json.Type.object)
    return "";
  auto p = key in doc;
  return p !is null && p.type == Json.Type.string ? p.get!string : "";
}

private long number(const Json doc, string key) @trusted {
  if (doc.type != Json.Type.object)
    return 0;
  auto p = key in doc;
  if (p is null)
    return 0;
  if (p.type == Json.Type.int_)
    return p.get!long;
  if (p.type == Json.Type.float_)
    return cast(long) p.get!double;
  return 0;
}

private string[] strings(const Json doc, string key) @trusted {
  string[] list;
  if (doc.type != Json.Type.object)
    return list;
  auto p = key in doc;
  if (p !is null && p.type == Json.Type.array)
    foreach (x; *p)
      if (x.type == Json.Type.string)
        list ~= x.get!string;
  return list;
}

///
unittest {
  import neko.platform.persistence.storages : MemoryBlobStore, MemoryDocumentStore;

  auto store = new MemoryDocumentStore;
  auto blobs = new MemoryBlobStore;
  assert(migrateSites(store, blobs).length == 0); // no subaccount yet

  store.store(subaccountsCollection, [
    "platform-open": parseJsonString(`{"key": "platform-open", "services": ["sites", "files"],
      "entitlements": [{"plan": "sites.site", "quota": 5}, {"plan": "files.storage", "quota": 50}],
      "tenants": [{"key": "default", "spaces": [{"key": "default", "sites": ["main"]}]}]}`),
    "shop-prod": parseJsonString(`{"key": "shop-prod", "sites": ["shop"],
      "roleCollections": [{"name": "Editors", "rights": ["sites.manage", "files.manage"], "members": ["bob"]}]}`)
  ]);
  store.store(landscapeCollection, ["global": parseJsonString(`{"name": "G",
    "entitlements": [{"plan": "sites.site", "quota": 10}]}`)]);
  store.store(plansCollection, ["sites.site": parseJsonString(`{"key": "sites.site", "meter": "sites"}`),
    "files.storage": parseJsonString(`{"key": "files.storage", "meter": "storageBytes"}`)]);
  Json file(string id, string field, string value) {
    return parseJsonString(`{"id": "` ~ id ~ `", "` ~ field ~ `": "` ~ value ~ `", "name": "` ~ id
        ~ `.txt", "size": 3, "createdAt": "2026-11-20T08:00:00Z", "modifiedAt": "2026-11-20T08:00:00Z"}`);
  }

  store.store(filesCollection, ["f1": file("f1", "site", "main"), "f2": file("f2", "site", "shop"),
    "f3": file("f3", "site", "gone"), "f4": file("f4", "subaccount", "shop-prod")]);
  blobs.put("main", "f1", cast(const(ubyte)[]) "png");
  blobs.put("shop", "f2", cast(const(ubyte)[]) "pdf");
  store.store(usageCollection, [
    "2026-11|main": serializeToJson(["month": "2026-11", "site": "main"]),
    "2026-11|shop": parseJsonString(`{"month": "2026-11", "site": "shop", "requests": 10, "bytesOut": 100,
      "peakStorageBytes": 7}`),
    "2026-11|outlet": parseJsonString(`{"month": "2026-11", "site": "outlet", "requests": 1, "bytesOut": 1,
      "peakStorageBytes": 1}`)
  ]);
  store.store(legacySitesCollection, ["main": parseJsonString(`{"key": "main"}`)]);

  auto notes = migrateSites(store, blobs);
  assert(notes.length == 4, notes.to!string);

  auto files = store.load(filesCollection);
  assert(text(files["f1"], "subaccount") == "platform-open" && "site" !in files["f1"]);
  assert(text(files["f2"], "subaccount") == "shop-prod" && text(files["f3"], "subaccount") == "platform-open");
  assert(cast(const(char)[]) blobs.get("platform-open", "f1") == "png" && blobs.get("main", "f1") is null);
  assert(cast(const(char)[]) blobs.get("shop-prod", "f2") == "pdf");

  auto usage = store.load(usageCollection);
  assert(usage.length == 2 && number(usage["2026-11|shop-prod"], "requests") == 10);
  assert(number(usage["2026-11|platform-open"], "requests") == 1); // "outlet" ran nowhere: the first subaccount

  auto subs = store.load(subaccountsCollection);
  assert(strings(subs["platform-open"], "services") == ["files"]);
  assert(subs["platform-open"]["entitlements"].length == 1 && "sites" !in subs["shop-prod"]);
  assert(strings(subs["shop-prod"]["roleCollections"][0], "rights") == ["files.manage"]);
  assert("sites" !in subs["platform-open"]["tenants"][0]["spaces"][0]);
  assert(store.load(landscapeCollection)["global"]["entitlements"].length == 0);
  assert("sites.site" !in store.load(plansCollection) && store.load(legacySitesCollection).length == 0);

  // the records still load, and a second run changes nothing
  auto f = deserializeJson!FileRecord(files["f2"]);
  assert(f.subaccount == "shop-prod" && f.site.length == 0);
  assert(migrateSites(store, blobs).length == 0);
}
