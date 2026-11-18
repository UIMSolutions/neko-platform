/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Neko Service Platform — hexagonal architecture:
///
///   presentation ──▶ ports.usecases ◀── application ──▶ domain
///                                          │
///   persistence / infrastructure ──▶ ports (repositories, storages, gateways, messaging)
module neko.platform;

public:
  import neko.platform.domain;
  import neko.platform.ports;
  import neko.platform.application;
  import neko.platform.persistence;
  import neko.platform.infrastructure;
  import neko.platform.presentation;
