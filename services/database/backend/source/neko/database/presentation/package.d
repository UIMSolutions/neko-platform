/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Präsentationsschicht: alle eingehenden Adapter. Die GtkD-Oberfläche (presentation.gui) ist ein eigenes Programm
/// und wird hier nicht eingebunden.
module neko.database.presentation;

public:
    import neko.database.presentation.cli;
    import neko.database.presentation.http;
    import neko.database.presentation.odata;
    import neko.database.presentation.rest;
    import neko.database.presentation.unix;
    import neko.database.presentation.web;
