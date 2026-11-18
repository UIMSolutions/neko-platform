/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven port for low-level data stores: named collections of JSON documents.
module neko.platform.ports.storages;

import vibe.data.json : Json;

@safe:

interface IDocumentStore {
  /// All documents of a collection, keyed by id (empty if the collection is new).
  Json[string] load(string collection);
  /// Replace the whole collection atomically.
  void store(string collection, Json[string] documents);
  /// Human-readable description for diagnostics ("memory", "file:data/open").
  string describe();
}
