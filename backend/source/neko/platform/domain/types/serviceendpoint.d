/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.types.serviceendpoint;

import std.algorithm : all, canFind, startsWith;
import std.ascii : isAlphaNum;
import std.string : strip;
import neko.platform.domain.exceptions;

@safe:

/// Where a service can be reached and how its health is checked.
struct ServiceEndpoint {
    string baseUrl;
    string healthPath = "/health";

    this(string baseUrl, string healthPath) pure {
        auto url = baseUrl.strip;
        while (url.length > 0 && url[$ - 1] == '/')
            url = url[0 .. $ - 1];
        if (url.length > 0 && !(url.startsWith("http://") || url.startsWith("https://")))
            throw new ValidationException("Base URL must start with http:// or https://: " ~ baseUrl);
        if (url.canFind(' '))
            throw new ValidationException("Base URL must not contain spaces");

        auto path = healthPath.strip;
        if (path.length == 0)
            path = "/health";
        if (path[0] != '/')
            path = "/" ~ path;

        this.baseUrl = url;
        this.healthPath = path;
    }

    /// A service without URL is catalogued but cannot be probed.
    bool isProbeable() const pure nothrow {
        return baseUrl.length > 0;
    }

    string healthUrl() const pure nothrow {
        return baseUrl ~ healthPath;
    }
}
///
unittest {
    import neko.platform.domain.types.servicename;

    assert(ServiceName("management").value == "management");
    bool failed;
    try
        ServiceName("Bad Name");
    catch (ValidationException)
        failed = true;
    assert(failed);

    auto ep = ServiceEndpoint("http://localhost:8098/", "api/v1/health");
    assert(ep.healthUrl() == "http://localhost:8098/api/v1/health");
    assert(!ServiceEndpoint("", "").isProbeable());
}
