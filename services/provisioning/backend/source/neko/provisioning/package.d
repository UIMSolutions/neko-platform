/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Identity Provisioning service — hexagonal architecture:
///   domain ← ports ← application ← persistence / infrastructure ← presentation
module neko.provisioning;

public {
  import uim.service;

  import neko.provisioning.helpers;
  import neko.provisioning.domain;
  import neko.provisioning.ports;
  import neko.provisioning.application;
  import neko.provisioning.persistence;
  import neko.provisioning.infrastructure;
  import neko.provisioning.presentation;
}
