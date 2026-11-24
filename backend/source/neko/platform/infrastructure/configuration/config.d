/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Type-safe platform configuration.
///
/// Precedence (lowest → highest):
///   1. compiled defaults (this struct; port = 8080 + domain level)
///   2. config file: NEKO_CONFIG_FILE, else config/default.{json,yaml,yml} or
///      backend/config/default.{json,yaml,yml}. Top-level keys apply to every
///      domain; a "domains": {"secret": {…}} section overrides per domain.
///   3. environment variables (NEKO_*, PORT on Cloud Foundry)
///   4. VCAP_SERVICES: credentials of the bound service named / tagged
///      "neko-platform-config" (same keys, including "domains")
module neko.platform.infrastructure.configuration.config;

import std.algorithm : canFind, map, splitter;
import std.array : array;
import std.conv : to;
import std.file : exists, readText, thisExePath;
import std.path : buildPath, dirName, extension;
import std.process : environment;
import std.string : strip, toLower;
import vibe.core.log : logWarn;
import vibe.data.json;
import neko.platform.domain.enumerations;

@safe:

enum vcapServiceName = "neko-platform-config";

struct PlatformConfig {
  string serviceName = "Neko Platform";
  /// "development" | "production" — informational, shown in the cockpit.
  string environment = "development";
  string host = "127.0.0.1";
  /// 0 = 8080 + domain level (open 8080 … secret 8083)
  ushort port = 0;
  /// "tcp" or "unix"
  string transport = "tcp";
  /// "" = /tmp/neko-platform-<domain>.sock
  string unixSocketPath = "";
  string logLevel = "info";
  /// "memory" (volatile) or "file" (JSON documents in <dataDir>/<domain>)
  string storage = "file";
  string dataDir = "data";
  /// Fiori app directory; "" = auto-detect (frontend, ../frontend).
  string frontendDir = "";
  string restPath = "/rest/v1/";
  string odataPath = "/odata/v4/platform";
  /// Require the XSUAA admin scope (…<adminScope>) for modifying requests.
  bool enforceScopes = false;
  string adminScope = "Admin";
  /// Health probe interval of the background worker (0 = off).
  int healthCheckIntervalSeconds = 0;
  int healthTimeoutSeconds = 5;
  long maxPayloadBytes = 10 * 1024 * 1024;
  /// First administrator, created when the instance has no web user yet.
  string adminUser = "admin";
  /// "" = generate one and print it once in the log.
  string adminPassword = "";
  /// Web sessions end after this many minutes without a request.
  int sessionIdleMinutes = 60;
  /// Largest file that can be uploaded to a subaccount's library.
  long maxUploadBytes = 50 * 1024 * 1024;
  /// Bytes of files per subaccount; 0 = no quota. Also read from the
  /// earlier key "siteQuotaBytes".
  long subaccountQuotaBytes = 0;
  /// Log files (application log, access log): "" = <dataDir>/<domain>/logs
  /// with storage "file" (none with "memory"); "none" = no log files.
  string logDir = "";
  /// Log files older than this many days are removed (0 = keep all).
  int logRetentionDays = 14;
  /// One line per HTTP request (log and access-YYYY-MM-DD.ndjson).
  bool accessLog = true;
  /// GET /metrics (Prometheus): "" = only from the local host; otherwise the
  /// scraper sends "Authorization: Bearer <metricsToken>".
  string metricsToken = "";
  /// Web application firewall: "block", "detect" (log only) or "off".
  string firewallMode = "block";
  /// Requests per client address and minute; 0 = no limit.
  int rateLimitPerMinute = 600;
  /// Firewall findings within 10 minutes that ban an address; 0 = never.
  int banAfterViolations = 20;
  int banMinutes = 15;
  /// Reverse proxies (addresses or CIDR, comma separated) whose
  /// X-Forwarded-For header names the real client, e.g. the approuter.
  string trustedProxies = "";

  /// Where the values came from (diagnostics).
  string[] sources = ["defaults"];

  /// Apply a flat JSON object of settings; numbers/booleans may be strings.
  void apply(Json values, string source) {
    if (values.type != Json.Type.object)
      return;
    void str(string key, ref string target) {
      if (auto v = key in values)
        target = v.type == Json.Type.string ? v.get!string : v.toString;
    }

    str("serviceName", serviceName);
    str("environment", environment);
    str("host", host);
    str("transport", transport);
    str("unixSocketPath", unixSocketPath);
    str("logLevel", logLevel);
    str("storage", storage);
    str("dataDir", dataDir);
    str("frontendDir", frontendDir);
    str("restPath", restPath);
    str("odataPath", odataPath);
    str("adminScope", adminScope);
    str("adminUser", adminUser);
    str("adminPassword", adminPassword);
    str("logDir", logDir);
    str("metricsToken", metricsToken);
    str("firewallMode", firewallMode);
    str("trustedProxies", trustedProxies);
    if ("rateLimitPerMinute" in values)
      rateLimitPerMinute = asNumber!int(values["rateLimitPerMinute"], "rateLimitPerMinute");
    if ("banAfterViolations" in values)
      banAfterViolations = asNumber!int(values["banAfterViolations"], "banAfterViolations");
    if ("banMinutes" in values)
      banMinutes = asNumber!int(values["banMinutes"], "banMinutes");
    if ("maxUploadBytes" in values)
      maxUploadBytes = asNumber!long(values["maxUploadBytes"], "maxUploadBytes");
    if ("siteQuotaBytes" in values) // earlier versions
      subaccountQuotaBytes = asNumber!long(values["siteQuotaBytes"], "siteQuotaBytes");
    if ("subaccountQuotaBytes" in values)
      subaccountQuotaBytes = asNumber!long(values["subaccountQuotaBytes"], "subaccountQuotaBytes");
    if ("logRetentionDays" in values)
      logRetentionDays = asNumber!int(values["logRetentionDays"], "logRetentionDays");
    if ("accessLog" in values)
      accessLog = asBool(values["accessLog"]);
    if ("sessionIdleMinutes" in values)
      sessionIdleMinutes = asNumber!int(values["sessionIdleMinutes"], "sessionIdleMinutes");
    if ("port" in values)
      port = asNumber!ushort(values["port"], "port");
    if ("enforceScopes" in values)
      enforceScopes = asBool(values["enforceScopes"]);
    if ("healthCheckIntervalSeconds" in values)
      healthCheckIntervalSeconds = asNumber!int(values["healthCheckIntervalSeconds"], "healthCheckIntervalSeconds");
    if ("healthTimeoutSeconds" in values)
      healthTimeoutSeconds = asNumber!int(values["healthTimeoutSeconds"], "healthTimeoutSeconds");
    if ("maxPayloadBytes" in values)
      maxPayloadBytes = asNumber!long(values["maxPayloadBytes"], "maxPayloadBytes");
    sources ~= source;
  }

  /// Apply the top-level settings, then the section for `domain`.
  void applyLayered(Json values, string source, SecurityDomain domain) {
    apply(values, source);
    if (values.type == Json.Type.object)
      if (auto domains = "domains" in values)
        if (domains.type == Json.Type.object)
          if (auto section = domain.label in *domains)
            apply(*section, source ~ "#" ~ domain.label);
  }

  /// Reject inconsistent settings early (at start-up, not at first request).
  void validate() const {
    if (transport != "tcp" && transport != "unix")
      throw new Exception("transport must be 'tcp' or 'unix', not '" ~ transport ~ "'");
    if (storage != "file" && storage != "memory")
      throw new Exception("storage must be 'file' or 'memory', not '" ~ storage ~ "'");
    if (healthCheckIntervalSeconds < 0 || healthTimeoutSeconds <= 0)
      throw new Exception("health check interval must be >= 0 and timeout > 0");
    if (maxPayloadBytes <= 0)
      throw new Exception("maxPayloadBytes must be positive");
    if (sessionIdleMinutes <= 0)
      throw new Exception("sessionIdleMinutes must be positive");
    if (maxUploadBytes <= 0 || subaccountQuotaBytes < 0)
      throw new Exception("maxUploadBytes must be positive and subaccountQuotaBytes >= 0");
    if (logRetentionDays < 0)
      throw new Exception("logRetentionDays must be >= 0");
    if (firewallMode != "block" && firewallMode != "detect" && firewallMode != "off")
      throw new Exception("firewallMode must be 'block', 'detect' or 'off', not '" ~ firewallMode ~ "'");
    if (rateLimitPerMinute < 0 || banAfterViolations < 0 || banMinutes <= 0)
      throw new Exception("rateLimitPerMinute and banAfterViolations must be >= 0, banMinutes > 0");
    foreach (p; proxyList)
      try {
        import neko.platform.domain.types.ipnetwork : IpNetwork;

        IpNetwork(p);
      } catch (Exception e)
        throw new Exception("trustedProxies: " ~ e.msg);
  }

  /// The entries of `trustedProxies`.
  string[] proxyList() const {
    import std.algorithm : filter;

    string[] result;
    foreach (p; trustedProxies.splitter(','))
      if (p.strip.length)
        result ~= p.strip;
    return result;
  }

  /// Directory of the log files; "" = no log files.
  string effectiveLogDir(SecurityDomain domain) const {
    if (logDir == "none")
      return "";
    if (logDir.length > 0)
      return buildPath(logDir, domain.label);
    return storage == "file" ? buildPath(effectiveDataDir(domain), "logs") : "";
  }

  /// Where uploaded files are kept (storage "file").
  string effectiveFilesDir(SecurityDomain domain) const {
    return buildPath(effectiveDataDir(domain), "files");
  }

  /// The largest request body the server accepts (uploads included).
  ulong maxRequestBytes() const {
    import std.algorithm : max;

    return cast(ulong) max(maxPayloadBytes * 2, maxUploadBytes + 1024 * 1024, 2 * 1024 * 1024);
  }

  ushort effectivePort(SecurityDomain domain) const {
    return port != 0 ? port : cast(ushort)(8080 + cast(int) domain);
  }

  string effectiveSocketPath(SecurityDomain domain) const {
    return unixSocketPath.length > 0 ? unixSocketPath : "/tmp/neko-platform-" ~ domain.label ~ ".sock";
  }

  /// Every domain keeps its data apart, even when sharing a data directory.
  string effectiveDataDir(SecurityDomain domain) const {
    return buildPath(dataDir, domain.label);
  }

  Json toJson(SecurityDomain domain) const {
    auto j = Json.emptyObject;
    j["serviceName"] = serviceName;
    j["domain"] = domain.label;
    j["environment"] = environment;
    j["transport"] = transport;
    if (transport == "unix")
      j["unixSocketPath"] = effectiveSocketPath(domain);
    else {
      j["host"] = host;
      j["port"] = effectivePort(domain);
    }
    j["logLevel"] = logLevel;
    j["storage"] = storage;
    if (storage == "file")
      j["dataDir"] = effectiveDataDir(domain);
    j["frontendDir"] = frontendDir;
    j["restPath"] = restPath;
    j["odataPath"] = odataPath;
    j["enforceScopes"] = enforceScopes;
    j["healthCheckIntervalSeconds"] = healthCheckIntervalSeconds;
    j["maxPayloadBytes"] = maxPayloadBytes;
    j["adminUser"] = adminUser; // the password is never shown
    j["sessionIdleMinutes"] = sessionIdleMinutes;
    j["maxUploadBytes"] = maxUploadBytes;
    j["subaccountQuotaBytes"] = subaccountQuotaBytes;
    j["logDir"] = effectiveLogDir(domain);
    j["logRetentionDays"] = logRetentionDays;
    j["accessLog"] = accessLog;
    j["metricsProtected"] = metricsToken.length > 0; // the token is never shown
    j["firewallMode"] = firewallMode;
    j["rateLimitPerMinute"] = rateLimitPerMinute;
    j["banAfterViolations"] = banAfterViolations;
    j["banMinutes"] = banMinutes;
    j["trustedProxies"] = trustedProxies;
    j["sources"] = Json(sources.map!(s => Json(s)).array);
    return j;
  }
}

/// Load the configuration for `domain` with the documented precedence.
PlatformConfig loadConfig(SecurityDomain domain) {
  PlatformConfig config;

  // 2. config file
  auto file = locateConfigFile();
  if (file.length > 0) {
    try
      config.applyLayered(readConfigFile(file), file, domain);
    catch (Exception e)
      logWarn("config: ignoring %s: %s", file, e.msg);
  }

  // 3. environment variables
  auto env = Json.emptyObject;
  static immutable string[2][] variables = [
    ["NEKO_SERVICE_NAME", "serviceName"], ["NEKO_ENVIRONMENT", "environment"],
    ["NEKO_HOST", "host"], ["NEKO_PORT", "port"], ["PORT", "port"],
    ["NEKO_TRANSPORT", "transport"], ["NEKO_UNIX_SOCKET", "unixSocketPath"],
    ["NEKO_LOG_LEVEL", "logLevel"], ["NEKO_STORAGE", "storage"], ["NEKO_DATA_DIR", "dataDir"],
    ["NEKO_FRONTEND_DIR", "frontendDir"], ["NEKO_ENFORCE_SCOPES", "enforceScopes"],
    ["NEKO_ADMIN_SCOPE", "adminScope"], ["NEKO_HEALTH_INTERVAL", "healthCheckIntervalSeconds"],
    ["NEKO_HEALTH_TIMEOUT", "healthTimeoutSeconds"], ["NEKO_MAX_PAYLOAD", "maxPayloadBytes"],
    ["NEKO_ADMIN_USER", "adminUser"], ["NEKO_ADMIN_PASSWORD", "adminPassword"],
    ["NEKO_SESSION_IDLE_MINUTES", "sessionIdleMinutes"], ["NEKO_MAX_UPLOAD", "maxUploadBytes"],
    ["NEKO_SITE_QUOTA", "siteQuotaBytes"], ["NEKO_SUBACCOUNT_QUOTA", "subaccountQuotaBytes"],
    ["NEKO_LOG_DIR", "logDir"], ["NEKO_LOG_RETENTION_DAYS", "logRetentionDays"],
    ["NEKO_ACCESS_LOG", "accessLog"], ["NEKO_METRICS_TOKEN", "metricsToken"],
    ["NEKO_FIREWALL_MODE", "firewallMode"], ["NEKO_RATE_LIMIT", "rateLimitPerMinute"],
    ["NEKO_BAN_AFTER", "banAfterViolations"], ["NEKO_BAN_MINUTES", "banMinutes"],
    ["NEKO_TRUSTED_PROXIES", "trustedProxies"],
  ];
  foreach (pair; variables) {
    auto value = (() @trusted => environment.get(pair[0], ""))();
    if (value.length > 0)
      env[pair[1]] = value;
  }
  try {
    if (env.length > 0)
      config.apply(env, "environment");
  } catch (Exception e)
    logWarn("config: invalid environment variable: %s", e.msg);

  // 4. VCAP_SERVICES
  auto vcap = (() @trusted => environment.get("VCAP_SERVICES", ""))();
  if (vcap.length > 0) {
    try {
      auto credentials = findServiceCredentials(parseJsonString(vcap), vcapServiceName);
      if (credentials.type == Json.Type.object)
        config.applyLayered(credentials, "VCAP_SERVICES", domain);
    } catch (Exception e)
      logWarn("config: cannot use VCAP_SERVICES: %s", e.msg);
  }

  return config;
}

/// Credentials of a bound service, found by instance name, binding name or tag.
Json findServiceCredentials(Json vcapServices, string nameOrTag) {
  if (vcapServices.type != Json.Type.object)
    return Json.undefined;
  foreach (label, instances; vcapServices.get!(Json[string])) {
    if (instances.type != Json.Type.array)
      continue;
    foreach (instance; instances.get!(Json[])) {
      if (instance.type != Json.Type.object)
        continue;
      bool match = stringField(instance, "name") == nameOrTag
        || stringField(instance, "binding_name") == nameOrTag;
      if (!match)
        if (auto tags = "tags" in instance)
          if (tags.type == Json.Type.array)
            foreach (tag; tags.get!(Json[]))
              if (tag.type == Json.Type.string && tag.get!string == nameOrTag)
                match = true;
      if (match)
        if (auto credentials = "credentials" in instance)
          return *credentials;
    }
  }
  return Json.undefined;
}

/// Read a JSON or YAML file into a Json tree.
Json readConfigFile(string file) @trusted {
  auto text = readText(file);
  switch (file.extension.toLower) {
  case ".yaml", ".yml":
    import dyaml : Loader;

    return yamlToJson(Loader.fromString(text, file).load());
  default:
    return parseJsonString(text);
  }
}

private Json yamlToJson(N)(N node) @trusted {
  import dyaml : NodeType;

  switch (node.type) {
  case NodeType.mapping:
    auto obj = Json.emptyObject;
    foreach (pair; node.mapping)
      obj[pair.key.as!string] = yamlToJson(pair.value);
    return obj;
  case NodeType.sequence:
    Json[] items;
    foreach (child; node.sequence)
      items ~= yamlToJson(child);
    return Json(items);
  case NodeType.boolean:
    return Json(node.as!bool);
  case NodeType.integer:
    return Json(node.as!long);
  case NodeType.decimal:
    return Json(node.as!double);
  case NodeType.null_:
    return Json(null);
  default:
    return Json(node.as!string);
  }
}

private string locateConfigFile() {
  auto explicit = (() @trusted => environment.get("NEKO_CONFIG_FILE", ""))();
  if (explicit.length > 0) {
    if (!(() @trusted => explicit.exists)())
      logWarn("config: NEKO_CONFIG_FILE '%s' does not exist", explicit);
    return (() @trusted => explicit.exists)() ? explicit : "";
  }

  string[] directories = [buildPath("config"), buildPath("backend", "config")];
  try {
    auto exeDir = (() @trusted => thisExePath.dirName)();
    directories ~= buildPath(exeDir, "..", "config"); // backend/build → backend/config
    directories ~= buildPath(exeDir, "config");
  } catch (Exception) {
  }
  foreach (dir; directories)
    foreach (name; ["default.json", "default.yaml", "default.yml"]) {
      auto candidate = buildPath(dir, name);
      if ((() @trusted => candidate.exists)())
        return candidate;
    }
  return "";
}

private string stringField(Json obj, string key) {
  if (auto v = key in obj)
    if (v.type == Json.Type.string)
      return v.get!string;
  return "";
}

private T asNumber(T)(Json value, string key) {
  try {
    if (value.type == Json.Type.string)
      return value.get!string.strip.to!T;
    if (value.type == Json.Type.int_)
      return value.get!long.to!T;
  } catch (Exception) {
  }
  throw new Exception("'" ~ key ~ "' must be a number, got " ~ value.toString);
}

private bool asBool(Json value) {
  if (value.type == Json.Type.bool_)
    return value.get!bool;
  return ["true", "1", "yes", "on"].canFind(value.type == Json.Type.string ? value.get!string.strip.toLower : value.toString);
}

///
unittest {
  PlatformConfig cfg;
  assert(cfg.effectivePort(SecurityDomain.secret) == 8083);

  auto file = parseJsonString(`{"port": 0, "storage": "memory", "domains": {"secret": {"port": "9443", "enforceScopes": "true"}}}`);
  cfg.applyLayered(file, "file", SecurityDomain.secret);
  assert(cfg.effectivePort(SecurityDomain.secret) == 9443 && cfg.enforceScopes && cfg.storage == "memory");
  assert(cfg.sources == ["defaults", "file", "file#secret"]);

  auto vcap = parseJsonString(`{"user-provided": [{"name": "x", "tags": ["neko-platform-config"], "credentials": {"logLevel": "debug"}}]}`);
  cfg.apply(findServiceCredentials(vcap, vcapServiceName), "vcap");
  assert(cfg.logLevel == "debug");
  cfg.validate();

  cfg.transport = "pipe";
  bool invalid;
  try
    cfg.validate();
  catch (Exception)
    invalid = true;
  assert(invalid);
}

///
unittest {
  import dyaml : Loader;

  auto json = (() @trusted => yamlToJson(Loader.fromString("port: 9000\nenforceScopes: true\ndomains:\n  open:\n    host: 0.0.0.0\n").load()))();
  PlatformConfig cfg;
  cfg.applyLayered(json, "yaml", SecurityDomain.open);
  assert(cfg.port == 9000 && cfg.enforceScopes && cfg.host == "0.0.0.0");
}
