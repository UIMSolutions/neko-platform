/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.infrastructure.configuration.config;

import std.file : exists, readText, thisExePath;
import std.path : buildPath, dirName;
import std.process : environment;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Type-safe service configuration.
///
/// Precedence (lowest → highest):
///   1. compiled defaults (this struct)
///   2. config file  (IDENTITY_DIRECTORY_CONFIG_FILE or config/default.json)
///   3. environment variables (IDENTITY_DIRECTORY_*, legacy IDS_HOST / IDS_PORT, PORT)
///   4. VCAP_SERVICES — credentials of a bound service named/tagged "identity-directory-config"
struct DirectoryConfig {
  string serviceName = "Identity Directory Service";
  string host = "0.0.0.0";
  ushort port = 8082;
  string logLevel = "info";
  /// "memory" (volatile) or "file" (JSON snapshots in dataDir, shared by server/CLI/GUI)
  string storage = "file";
  string dataDir = "data";
  string defaultTenant = "default";
  string odataPath = "/odata/v4/identity-directory";
  string scimPath = "/scim/v2";
  /// Run housekeeping every N seconds in the server (0 = off).
  int housekeepingIntervalSeconds = 60;
  string[] housekeepingTenants = ["default"];
  /// Install the predefined password policies and the enterprise user schema on start.
  bool seedContent = true;
  /// PBKDF2-HMAC-SHA256 work factor for passwords and client secrets.
  int passwordHashIterations = 120_000;
  /// Keep audit events for N days (0 = forever).
  int auditRetentionDays = 365;
  /// POST domain events to this URL (SAP Event Mesh webhook, ...; "" = log only).
  string eventWebhookUrl;
  /// Serve the Fiori app from this directory at "/" (local development; "" = off).
  string frontendDir = "../frontend";

  /// Where the values came from (for diagnostics).
  string[] sources = ["defaults"];

  /// Apply a flat JSON object of settings (strings are coerced).
  void apply(Json values, string source) {
    if (values.type != Json.Type.object)
      return;
    if (auto v = "serviceName" in values) serviceName = jsonText(*v);
    if (auto v = "host" in values) host = jsonText(*v);
    if (auto v = "port" in values) port = cast(ushort) jsonLong(*v, port);
    if (auto v = "logLevel" in values) logLevel = jsonText(*v);
    if (auto v = "storage" in values) storage = jsonText(*v);
    if (auto v = "dataDir" in values) dataDir = jsonText(*v);
    if (auto v = "defaultTenant" in values) defaultTenant = jsonText(*v);
    if (auto v = "odataPath" in values) odataPath = jsonText(*v);
    if (auto v = "scimPath" in values) scimPath = jsonText(*v);
    if (auto v = "frontendDir" in values) frontendDir = jsonText(*v);
    if (auto v = "eventWebhookUrl" in values) eventWebhookUrl = jsonText(*v);
    if (auto v = "housekeepingIntervalSeconds" in values)
      housekeepingIntervalSeconds = cast(int) jsonLong(*v, housekeepingIntervalSeconds);
    if (auto v = "housekeepingTenants" in values)
      housekeepingTenants = jsonStrings(*v);
    if (auto v = "seedContent" in values)
      seedContent = jsonBool(*v, seedContent);
    if (auto v = "passwordHashIterations" in values)
      passwordHashIterations = cast(int) jsonLong(*v, passwordHashIterations);
    if (auto v = "auditRetentionDays" in values)
      auditRetentionDays = cast(int) jsonLong(*v, auditRetentionDays);
    sources ~= source;
  }

  bool usesFileStorage() const {
    return storage == "file";
  }

  Json toJson() const {
    auto tenants = Json.emptyArray;
    foreach (t; housekeepingTenants)
      tenants ~= Json(t);
    auto origins = Json.emptyArray;
    foreach (s; sources)
      origins ~= Json(s);
    return Json.emptyObject
      .set("serviceName", serviceName)
      .set("host", host)
      .set("port", port)
      .set("logLevel", logLevel)
      .set("storage", storage)
      .set("dataDir", dataDir)
      .set("defaultTenant", defaultTenant)
      .set("odataPath", odataPath)
      .set("scimPath", scimPath)
      .set("housekeepingIntervalSeconds", housekeepingIntervalSeconds)
      .set("housekeepingTenants", tenants)
      .set("seedContent", seedContent)
      .set("passwordHashIterations", passwordHashIterations)
      .set("auditRetentionDays", auditRetentionDays)
      .set("eventWebhookUrl", eventWebhookUrl)
      .set("frontendDir", frontendDir)
      .set("sources", origins);
  }
}

/// Load configuration with the documented precedence.
DirectoryConfig loadConfig() {
  DirectoryConfig config;

  // 2. config file
  auto file = locateConfigFile();
  if (file.length > 0) {
    try {
      config.apply(parseJsonString((() @trusted => readText(file))()), file);
    } catch (Exception e) {
      logWarn("identity-directory: ignoring config file %s: %s", file, e.msg);
    }
  }

  // 3. environment variables
  auto env = Json.emptyObject;
  void fromEnv(string variable, string key) {
    auto value = environment.get(variable, "");
    if (value.length > 0)
      env[key] = value;
  }
  fromEnv("IDS_HOST", "host"); // legacy names of the previous version
  fromEnv("IDS_PORT", "port");
  enum p = "IDENTITY_DIRECTORY_";
  fromEnv(p ~ "SERVICE_NAME", "serviceName");
  fromEnv(p ~ "HOST", "host");
  fromEnv(p ~ "PORT", "port");
  fromEnv("PORT", "port"); // Cloud Foundry / Kubernetes
  fromEnv(p ~ "LOG_LEVEL", "logLevel");
  fromEnv(p ~ "STORAGE", "storage");
  fromEnv(p ~ "DATA_DIR", "dataDir");
  fromEnv(p ~ "DEFAULT_TENANT", "defaultTenant");
  fromEnv(p ~ "ODATA_PATH", "odataPath");
  fromEnv(p ~ "SCIM_PATH", "scimPath");
  fromEnv(p ~ "HOUSEKEEPING_INTERVAL", "housekeepingIntervalSeconds");
  fromEnv(p ~ "HOUSEKEEPING_TENANTS", "housekeepingTenants");
  fromEnv(p ~ "SEED_CONTENT", "seedContent");
  fromEnv(p ~ "PASSWORD_HASH_ITERATIONS", "passwordHashIterations");
  fromEnv(p ~ "AUDIT_RETENTION_DAYS", "auditRetentionDays");
  fromEnv(p ~ "EVENT_WEBHOOK_URL", "eventWebhookUrl");
  fromEnv(p ~ "FRONTEND_DIR", "frontendDir");
  try {
    if (env.length > 0)
      config.apply(env, "environment");
  } catch (Exception e) {
    logWarn("identity-directory: invalid environment configuration: %s", e.msg);
  }

  // 4. VCAP_SERVICES
  auto vcap = environment.get("VCAP_SERVICES", "");
  if (vcap.length > 0) {
    try {
      auto credentials = findServiceCredentials(parseJsonString(vcap), "identity-directory-config");
      if (credentials.type == Json.Type.object)
        config.apply(credentials, "VCAP_SERVICES");
    } catch (Exception e) {
      logWarn("identity-directory: cannot parse VCAP_SERVICES: %s", e.msg);
    }
  }

  return config;
}

/// Find the credentials of a bound service by instance name, binding name or tag.
Json findServiceCredentials(Json vcapServices, string nameOrTag) {
  if (vcapServices.type != Json.Type.object)
    return Json.undefined;
  foreach (label, instances; vcapServices.get!(Json[string])) {
    if (instances.type != Json.Type.array)
      continue;
    foreach (instance; instances.get!(Json[])) {
      bool match = instance.fieldString("name") == nameOrTag
        || instance.fieldString("binding_name") == nameOrTag
        || instance.fieldStrings("tags").canFind(nameOrTag);
      if (match && "credentials" in instance)
        return instance["credentials"];
    }
  }
  return Json.undefined;
}

private string locateConfigFile() {
  auto explicit = environment.get("IDENTITY_DIRECTORY_CONFIG_FILE", "");
  if (explicit.length > 0)
    return explicit.exists ? explicit : "";

  string[] candidates = [buildPath("config", "default.json"), buildPath("backend", "config", "default.json")];
  try {
    auto exeDir = (() @trusted => thisExePath.dirName)();
    candidates ~= buildPath(exeDir, "..", "config", "default.json");
  } catch (Exception) {
  }
  foreach (c; candidates)
    if (c.exists)
      return c;
  return "";
}

///
unittest {
  mixin(ShowTest!("DirectoryConfig"));

  DirectoryConfig cfg;
  cfg.apply(parseJsonString(`{"port": 9000, "storage": "memory", "housekeepingTenants": "a, b", "seedContent": "off",
    "passwordHashIterations": "1000"}`), "test");
  assert(cfg.port == 9000);
  assert(!cfg.usesFileStorage);
  assert(cfg.housekeepingTenants == ["a", "b"]);
  assert(!cfg.seedContent && cfg.passwordHashIterations == 1000);

  auto vcap = parseJsonString(`{"user-provided": [{"name": "identity-directory-config", "credentials": {"port": "9100"}}]}`);
  cfg.apply(findServiceCredentials(vcap, "identity-directory-config"), "vcap");
  assert(cfg.port == 9100);
}
