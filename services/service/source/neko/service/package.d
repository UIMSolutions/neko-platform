/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Umbrella module of the service library.
///
/// The protocol adapters are opt-in and must be imported explicitly, so their
/// names never clash with service specific adapters:
///   import neko.service.presentation.odata;  // OData v4 (Fiori)
///   import neko.service.presentation.cli;    // command line
///   import neko.service.presentation.gui;    // GtkD desktop GUI
module neko.service;

public {
  import uim.framework;
  import uim.services;

  import neko.service.application;
  import neko.service.classes;
  import neko.service.domain;
  import neko.service.exceptions;
  import neko.service.helpers;
  import neko.service.interfaces;
  import neko.service.mixins;
  import neko.service.ports;
  import neko.service.persistence;
  import neko.service.infrastructure;
  import neko.service.presentation;
  import neko.service.tests;
  import neko.service.udas;
}
