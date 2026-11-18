/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Document stores: volatile memory and JSON files (one file per collection).
module neko.platform.persistence.storages;

import std.file : exists, mkdirRecurse, readText, rename, write;
import std.path : buildPath;
import vibe.data.json;
import neko.platform.ports.storages;

@safe:

class MemoryDocumentStore : IDocumentStore {
  private Json[string][string] collections;

  Json[string] load(string collection) {
    if (auto docs = collection in collections)
      return (*docs).dup;
    return null;
  }

  void store(string collection, Json[string] documents) {
    collections[collection] = documents.dup;
  }

  string describe() {
    return "memory";
  }
}

/// `<dir>/<collection>.json`, written via a temporary file and rename so a
/// crash never leaves a half-written collection. The server and the CLI share
/// the same directory, so every load reads the current file.
class JsonFileDocumentStore : IDocumentStore {
  private string directory;

  this(string directory) {
    this.directory = directory;
  }

  Json[string] load(string collection) {
    auto file = path(collection);
    if (!(() @trusted => file.exists)())
      return null;
    auto json = parseJsonString((() @trusted => readText(file))());
    Json[string] result;
    if (json.type != Json.Type.object)
      return result;
    foreach (key, value; json.get!(Json[string]))
      result[key] = value;
    return result;
  }

  void store(string collection, Json[string] documents) {
    () @trusted { mkdirRecurse(directory); }();
    auto json = Json.emptyObject;
    foreach (key, value; documents)
      json[key] = value;
    auto file = path(collection);
    auto temp = file ~ ".tmp";
    () @trusted {
      write(temp, json.toPrettyString);
      rename(temp, file);
    }();
  }

  string describe() {
    return "file:" ~ directory;
  }

  private string path(string collection) {
    return buildPath(directory, collection ~ ".json");
  }
}

///
unittest {
  import std.file : tempDir, rmdirRecurse;
  import std.uuid : randomUUID;

  auto dir = buildPath(tempDir, "neko-store-" ~ randomUUID.toString);
  scope (exit)
    () @trusted { if (dir.exists) rmdirRecurse(dir); }();

  IDocumentStore[] stores = [cast(IDocumentStore) new MemoryDocumentStore, new JsonFileDocumentStore(dir)];
  foreach (store; stores) {
    assert(store.load("x").length == 0);
    store.store("x", ["a": Json(["n": Json(1)])]);
    auto back = store.load("x");
    assert(back.length == 1 && back["a"]["n"].get!int == 1);
  }
}
