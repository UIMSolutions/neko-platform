/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Identity Authentication service (SAP Cloud Identity Services – Authentication style).
///
/// Hexagonal layout:
///   domain → ports → application → persistence / infrastructure → presentation
module neko.service.authentication;

public {
  import uim.platform.service;

  import neko.service.authentication.domain;
  import neko.service.authentication.ports;
  import neko.service.authentication.application;
  import neko.service.authentication.persistence;
  import neko.service.authentication.infrastructure;
  import neko.service.authentication.presentation;
}
