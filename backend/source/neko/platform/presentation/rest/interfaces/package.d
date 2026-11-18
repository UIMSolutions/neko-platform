/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// vibe.d REST interfaces — the wire contract shared by the server-side
/// services and the RestInterfaceClient-based clients.
///
/// The `actor` parameters are filled server-side by `@before!actorOf` from the
/// Authorization / X-User-Id headers; they are never sent over the wire.
module neko.platform.presentation.rest.interfaces;

public:
  import neko.platform.presentation.rest.interfaces.overview;
  import neko.platform.presentation.rest.interfaces.services;
  import neko.platform.presentation.rest.interfaces.transfers;
