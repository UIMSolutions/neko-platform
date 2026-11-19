/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Kommandozeile: SQL-Shell und Skripte (Programm hdb-cli, dub run --config=cli), entweder gegen eine Datenbank
/// im eigenen Prozess oder als Client über den Unix-Socket eines laufenden Servers. Die Shell kennt nur
/// ISqlUseCase; RemoteSqlClient ist dessen Umsetzung über den Socket.
module neko.database.presentation.cli;

public:
    import neko.database.presentation.cli.console;
    import neko.database.presentation.cli.format;
    import neko.database.presentation.cli.interfaces;
    import neko.database.presentation.cli.options;
    import neko.database.presentation.cli.remote;
    import neko.database.presentation.cli.shell;
    import neko.database.presentation.cli.statements;
    import neko.database.presentation.cli.cloud;
    import neko.database.presentation.cli.cloud_http;
