/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Shared helpers of the REST services.
module neko.service.platform.presentation.rest.services.support;

import vibe.http.common : HTTPStatusException;
import neko.service.platform.domain : PlatformException;

@safe:

/// Run `action`; business exceptions become HTTP errors with their status code
/// (rendered by vibe.d as {"statusMessage": "..."}).
auto guarded(T)(scope T delegate() @safe action) {
  try
    return action();
  catch (PlatformException e)
    throw new HTTPStatusException(e.code, e.msg);
}
