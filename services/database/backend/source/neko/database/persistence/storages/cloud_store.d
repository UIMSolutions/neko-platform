/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Ablage des Cloud-Zustands: eine JSON-Datei, atomar über eine temporäre Datei ersetzt.
module neko.database.persistence.storages.cloud_store;

import neko.database.ports.storages : ICloudStateStore;
import std.file : exists, mkdirRecurse, readText, rename, write;
import std.path : dirName;
import vibe.data.json : Json, parseJsonString;

@safe:

final class FileCloudStateStore : ICloudStateStore {
    private string path;

    this(string path) {
        this.path = path;
    }

    Json load() {
        if (!exists(path))
            return Json.emptyObject;
        auto text = readText(path);
        return text.length ? parseJsonString(text, path) : Json.emptyObject;
    }

    void save(Json state) {
        auto dir = dirName(path);
        if (dir.length && !exists(dir))
            mkdirRecurse(dir);
        auto tmp = path ~ ".tmp";
        write(tmp, state.toPrettyString);
        rename(tmp, path);
    }
}

final class MemoryCloudStateStore : ICloudStateStore {
    private Json state;

    this() {
        state = Json.emptyObject;
    }

    Json load() {
        return parseJsonString(state.toString);
    }

    void save(Json s) {
        state = parseJsonString(s.toString);
    }
}

unittest {
    import std.file : remove, tempDir;
    import std.path : buildPath;

    auto path = buildPath(tempDir, "hdb-cloud-test.json");
    scope (exit)
        if (exists(path))
            remove(path);
    auto store = new FileCloudStateStore(path);
    assert(store.load().length == 0);
    store.save(Json(["a": Json(1)]));
    assert(new FileCloudStateStore(path).load()["a"].get!int == 1);
}
