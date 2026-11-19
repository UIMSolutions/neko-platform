/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Identity Directory service — hexagonal architecture:
///   domain ← ports ← application ← persistence / infrastructure ← presentation
module neko.directory;

public {
  import uim.platform.service;

  import neko.directory.helpers;
  import neko.directory.domain;
  import neko.directory.ports;
  import neko.directory.application;
  import neko.directory.persistence;
  import neko.directory.infrastructure;
  import neko.directory.presentation;
}
