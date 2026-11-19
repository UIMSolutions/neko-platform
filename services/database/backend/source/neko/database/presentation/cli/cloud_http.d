/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// HTTP-Übertragung für `hdb-cli cloud` (vibe.d-Client) und der Ablauf mit An- und Abmeldung.
module neko.database.presentation.cli.cloud_http;

import neko.database.presentation.cli.cloud;
import neko.database.presentation.cli.console : ConsoleOutput, readSecret;
import neko.database.presentation.cli.interfaces : ICliOutput;
import std.exception : enforce;
import std.process : environment;
import std.string : strip;
import vibe.core.core : runTask, runEventLoop, exitEventLoop;
import vibe.data.json : Json, parseJsonString;
import vibe.http.client : HTTPClientRequest, HTTPClientResponse, requestHTTP;
import vibe.http.common : HTTPMethod, httpMethodFromString;
import vibe.stream.operations : readAllUTF8;

@safe:

final class HttpCloudTransport : ICloudTransport {
    private string base;
    string token;

    this(string server) {
        base = server.strip;
        while (base.length && base[$ - 1] == '/')
            base = base[0 .. $ - 1];
        enforce(base.length > 7, "Invalid --server URL");
    }

    Json request(string method, string path, Json body_ = Json.undefined) {
        Json result;
        int status;
        string text;
        requestHTTP(base ~ path, (scope HTTPClientRequest req) {
            req.method = httpMethodFromString(method);
            if (token.length)
                req.headers["Authorization"] = "Bearer " ~ token;
            if (body_.type != Json.Type.undefined)
                req.writeJsonBody(body_);
            else if (method == "POST" || method == "PUT" || method == "PATCH")
                req.writeJsonBody(Json.emptyObject);
        }, (scope HTTPClientResponse res) {
            status = res.statusCode;
            text = res.bodyReader.readAllUTF8();
        });
        if (status == 204 || text.strip.length == 0)
            return Json.undefined;
        try
            result = parseJsonString(text);
        catch (Exception)
            result = Json(text);
        if (status >= 400) {
            auto msg = result.type == Json.Type.object ? result["statusMessage"].opt!string(text) : text;
            throw new Exception(msg ~ " (HTTP " ~ (cast(int) status).to!string ~ ")");
        }
        return result;
    }

    void login(string tenant, string user, string password) {
        auto r = request("POST", "/api/v1/auth/login", Json(["tenant": Json(tenant), "user": Json(user),
                "password": Json(password)]));
        token = r["token"].get!string;
    }

    void logout() {
        request("POST", "/api/v1/auth/logout");
        token = null;
    }
}

private import std.conv : to;

/// `hdb-cli cloud …`: meldet an, führt den Befehl aus und meldet wieder ab.
int runCloud(string program, string[] args) @trusted {
    auto output = new ConsoleOutput;
    CloudCommand c;
    try
        c = parseCloudArgs(args);
    catch (Exception e) {
        output.error(program ~ ": " ~ e.msg ~ "\n");
        return 2;
    }
    if (c.words.length == 0 || "help" in c.options) {
        output.write(cloudUsage(program));
        return c.words.length == 0 && "help" !in c.options ? 2 : 0;
    }
    int status = 1;
    runTask(() nothrow {
        try {
            auto http = new HttpCloudTransport(c.server.length ? c.server : environment.get("HDB_SERVER", "http://localhost:8080"));
            bool own;
            auto user = c.user.length ? c.user : environment.get("HDB_USER", "");
            if (user.length) {
                auto password = environment.get("HDB_PASSWORD", null);
                if (password is null)
                    password = readSecret("Password for " ~ user ~ (c.tenant.length ? "@" ~ c.tenant : "") ~ ": ");
                enforce(password !is null, "No password: set HDB_PASSWORD or run on a terminal");
                http.login(c.tenant, user, password);
                own = true;
            } else {
                http.token = environment.get("HDB_TOKEN", "");
                enforce(http.token.length, "Sign in with --user (and HDB_PASSWORD), or pass a token in HDB_TOKEN");
            }
            void signOff() {
                if (own)
                    try
                        http.logout();
                    catch (Exception) {
                    }
            }

            scope (exit)
                signOff();
            status = runCloudCommand(c, http, output, (string k) @safe => environment.get(k, null));
        } catch (Exception e) {
            try
                output.error(program ~ ": " ~ e.msg ~ "\n");
            catch (Exception) {
            }
            status = 1;
        }
        exitEventLoop();
    });
    runEventLoop();
    return status;
}
