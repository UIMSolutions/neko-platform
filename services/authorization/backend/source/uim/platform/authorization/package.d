/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Authorization Management Service in the style of SAP Cloud Identity Services
/// AMS: applications and their APIs, base / custom authorization policies with
/// attribute conditions, policy assignments to users and groups, runtime
/// authorization decisions and a decision log.
///
/// Layers (hexagonal / clean architecture):
///   domain → ports → application → persistence / infrastructure → presentation
module neko.service.authorization;

public:
  import uim.oop;
  import neko.service;

  import neko.service.authorization.domain;
  import neko.service.authorization.ports;
  import neko.service.authorization.application;
  import neko.service.authorization.persistence;
  import neko.service.authorization.infrastructure;
  import neko.service.authorization.presentation;
