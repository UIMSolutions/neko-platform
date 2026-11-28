/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.application.dtos.requests.packages.import_;

import std.typecons : Nullable;
import vibe.data.serialization : optional;

@safe:

struct ImportPackageRequest {
  /// The transfer document (JSON text) produced by an export.
  string document;
}
