/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Identity Authentication service (SAP Cloud Identity Services – Authentication style).
///
/// Hexagonal layout:
///   domain → ports → application → persistence / infrastructure → presentation
module neko.authentication;

public:
  import uim.oop;
  import uim.service;

  import neko.authentication.domain;
  import neko.authentication.ports;
  import neko.authentication.application;
  import neko.authentication.persistence;
  import neko.authentication.infrastructure;
  import neko.authentication.presentation;

