/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Object Store service — hexagonal architecture:
///   domain ← ports ← application ← persistence / infrastructure ← presentation
module neko.objects;

public {
  import uim.platform.service;

  import neko.objects.helpers;
  import neko.objects.domain;
  import neko.objects.ports;
  import neko.objects.application;
  import neko.objects.persistence;
  import neko.objects.infrastructure;
  import neko.objects.presentation;
}
