/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.files.upload;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:
struct UploadFileRequest {
  /// Key of the subaccount whose library receives the file.
  string subaccount;
  /// Original file name (sanitised; the content type follows its extension).
  string name;
  /// The uploaded content: a local temporary file …
  @optional string sourcePath;
  /// … or the bytes themselves (CLI, tests).
  @optional immutable(ubyte)[] data;
  @optional string description;
  @optional bool isPublic;
}
    