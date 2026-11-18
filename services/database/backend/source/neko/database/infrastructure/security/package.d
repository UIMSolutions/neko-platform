/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Anmeldung an HTTP (Bearer, Cookie, XSUAA-Header) und Passwort-Kryptografie.
module neko.database.infrastructure.security;

public:
    import neko.database.infrastructure.security.crypto;
    import neko.database.infrastructure.security.gate;
