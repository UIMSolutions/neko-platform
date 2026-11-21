module neko.platform.persistence.repositories.mixins.documentcollection;

import neko.platform.ports.storages;
import vibe.data.json;
import std.array;
import std.conv;

/// Generic load/convert/store logic shared by the repositories.
mixin template DocumentCollection(Entity, Record, string collection) {
  private IDocumentStore store;

  this(IDocumentStore store) {
    this.store = store;
  }

  private Entity[] loadAll() {
    Entity[] result;
    foreach (doc; store.load(collection))
      result ~= toEntity(deserializeJson!Record(doc));
    return result;
  }

  private bool find(string id, out Entity entity) {
    auto docs = store.load(collection);
    if (auto doc = id in docs) {
      entity = toEntity(deserializeJson!Record(*doc));
      return true;
    }
    return false;
  }

  private void put(string id, const Entity entity) {
    auto docs = store.load(collection);
    docs[id] = serializeToJson(toRecord(entity));
    store.store(collection, docs);
  }
}