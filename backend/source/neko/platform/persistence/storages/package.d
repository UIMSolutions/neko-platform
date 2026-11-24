/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Document stores (volatile memory, JSON files — one file per collection)
/// and blob stores for file content (memory, file system).
module neko.platform.persistence.storages;

import std.file : copy, DirEntry, dirEntries, exists, isDir, mkdirRecurse, readText, rename, SpanMode, write;
static import std.file;
import std.path : buildPath, dirName;
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

/// Blobs in memory (storage "memory", tests).
class MemoryBlobStore : IBlobStore {
  private immutable(ubyte)[][string][string] folders;

  BlobInfo putFile(string folder, string id, string source) {
    auto data = (() @trusted => cast(immutable(ubyte)[]) std.file.read(source))();
    return put(folder, id, data);
  }

  BlobInfo put(string folder, string id, const(ubyte)[] data) {
    folders[folder][id] = data.idup;
    return BlobInfo(cast(long) data.length, sha256Of(data));
  }

  string localPath(string folder, string id) {
    return "";
  }

  ubyte[] get(string folder, string id) {
    if (auto f = folder in folders)
      if (auto d = id in *f)
        return (*d).dup;
    return null;
  }

  bool remove(string folder, string id) {
    if (auto f = folder in folders)
      return (*f).remove(id);
    return false;
  }

  long usage(string folder) {
    long n;
    if (auto f = folder in folders)
      foreach (d; *f)
        n += d.length;
    return n;
  }

  long available() {
    return -1;
  }

  string describe() {
    return "memory";
  }
}

/// `<directory>/<folder>/<id>`: one directory per subaccount, one file per blob
/// (named by its generated id, so client names never reach the file system).
/// Written via a temporary file and rename.
class FileSystemBlobStore : IBlobStore {
  private string directory;

  this(string directory) {
    this.directory = directory;
  }

  BlobInfo putFile(string folder, string id, string source) {
    auto target = path(folder, id);
    auto temp = target ~ ".tmp";
    () @trusted {
      mkdirRecurse(dirName(target));
      try
        rename(source, temp); // same volume: no copy
      catch (Exception)
        copy(source, temp);
    }();
    return commit(temp, target);
  }

  BlobInfo put(string folder, string id, const(ubyte)[] data) {
    auto target = path(folder, id);
    auto temp = target ~ ".tmp";
    () @trusted {
      mkdirRecurse(dirName(target));
      write(temp, data);
    }();
    return commit(temp, target);
  }

  string localPath(string folder, string id) {
    auto p = path(folder, id);
    return (() @trusted => p.exists)() ? p : "";
  }

  ubyte[] get(string folder, string id) {
    auto p = path(folder, id);
    return (() @trusted => p.exists ? cast(ubyte[]) std.file.read(p) : null)();
  }

  bool remove(string folder, string id) {
    auto p = path(folder, id);
    return () @trusted {
      if (!p.exists)
        return false;
      std.file.remove(p);
      return true;
    }();
  }

  long usage(string folder) {
    auto dir = buildPath(directory, checked(folder));
    return () @trusted {
      long n;
      if (dir.exists && dir.isDir)
        foreach (DirEntry e; dirEntries(dir, SpanMode.shallow))
          if (e.isFile)
            n += e.size;
      return n;
    }();
  }

  long available() {
    return freeBytes(directory);
  }

  string describe() {
    return "file:" ~ directory;
  }

  private BlobInfo commit(string temp, string target) @trusted {
    import std.digest.sha : SHA256;
    import std.stdio : File;

    SHA256 sha;
    long size;
    {
      auto f = File(temp, "rb");
      foreach (chunk; f.byChunk(64 * 1024)) {
        sha.put(chunk);
        size += chunk.length;
      }
    }
    rename(temp, target);
    return BlobInfo(size, toHex(sha.finish()));
  }

  private string path(string folder, string id) {
    return buildPath(directory, checked(folder), checked(id));
  }
}

/// Folder and blob names are platform-generated (subaccount keys, ids);
/// refuse anything else. A '.' is fine after the first character, so "." and
/// ".." can never be named.
private string checked(string name) pure {
  import std.algorithm : all;
  import std.ascii : isAlphaNum;

  if (name.length == 0 || name.length > 64 || name[0] == '.'
      || !name.all!(c => (c.isAlphaNum && c < 0x80) || c == '-' || c == '_' || c == '.'))
    throw new Exception("Invalid blob name '" ~ name ~ "'");
  return name;
}

private string sha256Of(const(ubyte)[] data) {
  import std.digest.sha : sha256Of;

  return toHex(sha256Of(data));
}

private string toHex(const(ubyte)[] digest) pure {
  import std.digest : toHexString, LetterCase;

  return toHexString!(LetterCase.lower)(digest).idup;
}

/// Free bytes on the volume holding `directory` (or its nearest existing parent).
long freeBytes(string directory) @trusted {
  version (Posix) {
    import core.sys.posix.sys.statvfs : statvfs, statvfs_t;
    import std.string : toStringz;

    auto dir = directory;
    while (dir.length && !dir.exists)
      dir = dir.dirName == dir ? "" : dir.dirName;
    statvfs_t st;
    if (statvfs((dir.length ? dir : ".").toStringz, &st) == 0)
      return cast(long) st.f_bavail * cast(long) st.f_frsize;
  }
  return -1;
}

///
unittest {
  import std.file : tempDir, rmdirRecurse;
  import std.uuid : randomUUID;

  auto dir = buildPath(tempDir, "neko-blobs-" ~ randomUUID.toString);
  scope (exit)
    () @trusted { if (dir.exists) rmdirRecurse(dir); }();
  auto source = buildPath(dir, "upload.tmp");
  () @trusted { mkdirRecurse(dir); write(source, "hello"); }();

  IBlobStore[] stores = [cast(IBlobStore) new MemoryBlobStore, new FileSystemBlobStore(buildPath(dir, "files"))];
  foreach (store; stores) {
    auto info = store.put("shop", "a1", cast(const(ubyte)[]) "hello");
    assert(info.size == 5 && info.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824");
    assert(cast(const(char)[]) store.get("shop", "a1") == "hello" && store.usage("shop") == 5);
    assert(store.remove("shop", "a1") && !store.remove("shop", "a1") && store.get("shop", "a1") is null);
  }
  auto fs = cast(FileSystemBlobStore) stores[1];
  auto moved = fs.putFile("shop", "b2", source);
  assert(moved.size == 5 && fs.localPath("shop", "b2").length > 0 && !(() @trusted => source.exists)());
  assert(fs.available != 0);
  assert(fs.put("shop.eu", "c3", cast(const(ubyte)[]) "x").size == 1); // subaccount keys may hold '.'
  foreach (bad; ["..", ".", "../x", "a/b", ".hidden"]) {
    bool refused;
    try
      fs.put(bad, "x", null);
    catch (Exception)
      refused = true;
    assert(refused, bad);
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
