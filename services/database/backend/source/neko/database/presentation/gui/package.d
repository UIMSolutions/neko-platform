/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Admin-Client mit GTK (GtkD). Ein eigenes Programm (dub build --config=gui), das den Server nur über seine
/// REST-API anspricht: dieselben Rechte, dieselbe Anmeldung wie jeder andere Client.
module neko.database.presentation.gui;

public:
    import neko.database.presentation.gui.models;
    import neko.database.presentation.gui.views;
    import neko.database.presentation.gui.controllers;
