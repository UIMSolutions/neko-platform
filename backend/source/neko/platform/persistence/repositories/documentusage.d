/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Repository implementations of the driven ports, on top of a document store.
module neko.platform.persistence.repositories.documentusage;

import vibe.data.json;
import neko.platform.domain;
import neko.platform.ports.repositories;
import neko.platform.ports.storages;
import neko.platform.persistence.mappers;
import neko.platform.persistence.records;
import neko.platform.persistence.repositories.mixins;

@safe:

class DocumentUsageRepository : IUsageRepository {
  private IDocumentStore store;

  this(IDocumentStore store) {
    this.store = store;
  }

  UsageRecord[] ofMonth(string month) {
    UsageRecord[] result;
    foreach (doc; store.load(usageCollection)) {
      auto u = toEntity(deserializeJson!UsageDocument(doc));
      if (u.month == month)
        result ~= u;
    }
    return result;
  }

  string[] months() {
    import std.algorithm : sort, uniq;
    import std.array : array;

    string[] list;
    foreach (doc; store.load(usageCollection))
      list ~= doc["month"].get!string;
    list.sort!((a, b) => a > b);
    return list.uniq.array;
  }

  void add(const(UsageRecord)[] deltas) {
    if (deltas.length == 0)
      return;
    auto docs = store.load(usageCollection);
    foreach (d; deltas) {
      auto key = d.month ~ "|" ~ d.subaccount;
      UsageRecord current = UsageRecord(d.month, d.subaccount);
      if (auto doc = key in docs)
        current = toEntity(deserializeJson!UsageDocument(*doc));
      current.merge(d);
      docs[key] = serializeToJson(toRecord(current));
    }
    store.store(usageCollection, docs);
  }
}

