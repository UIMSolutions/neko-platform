/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.database;

@safe:

public:
    import uim.oop;

    import neko.database.domain;
    import neko.database.ports;
    import neko.database.application;
    import neko.database.persistence;
    import neko.database.infrastructure;
    import neko.database.presentation;

    import std.algorithm;
    import std.array;
    import std.conv;
    import std.functional;
    import std.path;
    import std.process;
    import std.string;
    import std.uni;
    import std.file;
    import std.stdio;

    import vibe.d;
