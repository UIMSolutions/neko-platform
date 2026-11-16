/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module app;

import neko.service.platform;
import std.conv;
import vibe.d;
import std.file;
import std.json;
import dyaml;

version (DomainOpen)
    enum selfDomain = SecurityDomain.offen;
else version (DomainRestricted)
    enum selfDomain = SecurityDomain.restricted;
else version (DomainConfidential)
    enum selfDomain = SecurityDomain.confidential;
else version (DomainSecret)
    enum selfDomain = SecurityDomain.secret;
else
    static assert(0, "Set one of DomainOpen, DomainRestricted, DomainConfidential, or DomainSecret");

// Capabilities based on the security domain
enum canExport = selfDomain != SecurityDomain.secret;
enum canImport = selfDomain != SecurityDomain.offen;

static if (canExport)
    import neko.service.platform.application.services.exporting;
static if (canImport)
    import neko.service.platform.application.services.importing;

/// Configuration for the server
struct ServerConfig {
    string bindAddress = "127.0.0.1";
    ushort port = 8080;
    string transport = "tcp";          // "tcp" oder "unix"
    string unixSocketPath = "/var/run/myfiori.sock";
}

/// Communication protocol configuration
struct ProtocolConfig {
    string protocol = "rest";          // "rest" oder "odata"
    bool enableBatchProcessing = false;
}

struct AppConfig {
    ServerConfig server;
    ProtocolConfig communication = ProtocolConfig.init;
    string environment = "development";
}

/// Lädt die Konfiguration wahlweise aus einer JSON- oder YAML-Datei
AppConfig loadConfiguration() {
    AppConfig config;

    if (exists("config.json")) {
        try {
            auto jsonContent = readFileUTF8("config.json");
            auto json = parseJson(jsonContent);
            deserializeJson(config, json);
            logInfo("Configuration successfully loaded from 'config.json'");
        } catch (Exception e) {
            logError("Error reading 'config.json': %s", e.msg);
        }
    } else if (exists("config.yaml") || exists("config.yml")) {
        string filename = exists("config.yaml") ? "config.yaml" : "config.yml";
        try {
            // Load the YAML configuration file
            Node root = Loader.fromFile(filename).load();

            if (root.containsKey("server")) {
                auto serverNode = root["server"];
                if (serverNode.containsKey("bindAddress"))
                    config.server.bindAddress = serverNode["bindAddress"].as!string;
                if (serverNode.containsKey("port"))
                    config.server.port = serverNode["port"].as!ushort;
                if (serverNode.containsKey("transport"))
                    config.server.transport = serverNode["transport"].as!string;
                if (serverNode.containsKey("unixSocketPath"))
                    config.server.unixSocketPath = serverNode["unixSocketPath"].as!string;
            }

            if (root.containsKey("communication")) {
                auto commNode = root["communication"];
                if (commNode.containsKey("protocol"))
                    config.communication.protocol = commNode["protocol"].as!string;
                if (commNode.containsKey("enableBatchProcessing"))
                    config.communication.enableBatchProcessing = commNode["enableBatchProcessing"].as!bool;
            }

            if (root.containsKey("environment"))
                config.environment = root["environment"].as!string;

            logInfo("Configuration successfully loaded from '%s'", filename);
        } catch (Exception e) {
            logError("Error reading '%s': %s", filename, e.msg);
        }
    } else {
        logInfo("No configuration file found (config.json / config.yaml). Using default values.");
    }

    return config;
}

void health(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeBody("ok " ~ selfDomain.to!string);
}

/// strict Content Security Policy: The UI loads nothing from external sources (important in isolated domains). 
void securityHeaders(HTTPServerRequest req, HTTPServerResponse res) {
    res.headers["Content-Security-Policy"] =
        "default-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";
    res.headers["X-Content-Type-Options"] = "nosniff";
    res.headers["Referrer-Policy"] = "no-referrer";
}

int main() {
    logInfo("Domain %s (export=%s, import=%s)", selfDomain, canExport, canImport);

    // Load configuration from file or use defaults
    auto config = loadConfiguration();

    auto router = new URLRouter;
    router.any("*", &securityHeaders);
    router.get("/health", &health);

    auto settings = new HTTPServerSettings;
    settings.port = config.server.port;
    settings.bindAddresses = [config.server.bindAddress];
    listenHTTP(settings, router);
    return runApplication();
}
