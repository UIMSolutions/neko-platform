/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Unix domain socket transport: serves the same router over a socket file
/// instead of TCP — for hosts where the platform must not open a network port
/// (e.g. behind a local reverse proxy, or in an air-gapped domain).
///
///   curl --unix-socket /tmp/neko-platform-secret.sock http://localhost/health
module neko.service.platform.presentation.unix;

public:
  import neko.service.platform.presentation.unix.controller;
  import neko.service.platform.presentation.unix.listener;
