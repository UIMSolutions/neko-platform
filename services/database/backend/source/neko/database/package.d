/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.database;

@safe:

public:
    import uim.oop;

    import neko.database.application;
    import neko.database.domain;
    import neko.database.infrastructure;
    import neko.database.presentation;
    import neko.database.adapters;

    import neko.database.adapters.inbound.admin_web;
    import neko.database.adapters.inbound.application_log;
    import neko.database.adapters.inbound.rest_api;
    import neko.database.adapters.inbound.security;
    import neko.database.adapters.outbound.file_tenant_storage;
    import neko.database.adapters.outbound.file_tenant_store;
    import neko.database.adapters.outbound.file_user_store;
    import neko.database.adapters.outbound.file_log_store;
    import neko.database.adapters.outbound.file_statement_log;
    import neko.database.adapters.outbound.openssl_credential_crypto;
    import neko.database.adapters.outbound.replication_http;

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
