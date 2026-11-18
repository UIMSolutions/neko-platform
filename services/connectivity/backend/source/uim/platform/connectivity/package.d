/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// ABAP environment service — hexagonal architecture:
///   domain ← ports ← application ← persistence / infrastructure ← presentation
module neko.connectivity;

public {
  import uim.service;

  import neko.connectivity.helpers;
  import neko.connectivity.domain;
  import neko.connectivity.ports;
  import neko.connectivity.application;
  import neko.connectivity.persistence;
  import neko.connectivity.infrastructure;
  import neko.connectivity.presentation;
}
