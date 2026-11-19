/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Command line driving adapter. Generic over the resource registry, so every
/// resource supports the same verbs — exactly like the REST/OData/GUI adapters.
module neko.directory.presentation.cli.commands;

import std.file : readText, exists;
import neko.directory;
import neko.directory.presentation.cli.args;
import neko.directory.presentation.resources;
import neko.directory.presentation.tabular;

mixin(ShowModule!());

@safe:

enum cliUsage = `neko-directory-cli — SCIM 2.0 identity directory administration (users, groups,
custom schemas, password policies, API clients, audit log)

Usage: neko-directory-cli <command> [arguments] [options]

Global options:
  --tenant=<id>        tenant (default: configured defaultTenant)
  --user=<id>          acting administrator (default: cli)
  --data-dir=<dir>     snapshot directory shared with server and GUI
  --storage=memory     volatile storage (testing)
  --json               machine readable JSON output

Commands:
  resources                              resource kinds and their actions
  seed                                   install the predefined password policies and the enterprise user schema
  stats                                  aggregated figures of the tenant
  housekeeping                           apply time driven transitions now (unlock, expiry, dynamic groups, retention)
  config                                 effective service configuration

  <resource> list   [--<field>=<value> ...]       filter by payload fields
  <resource> get    <id|name>
  <resource> create --<field>=<value> ... [--file=body.json]
  <resource> update <id|name> --<field>=<value> ...
  <resource> delete <id|name>
  <resource> fields                               settable fields
  <resource> <action> <id|name> [--<param>=..]    e.g. groups add-member Sales --member=jane

Resources: %s

Values: lists "a,b" · structured fields (emails, members, attributes,
extended-attributes) as JSON · "@file" reads the value from a file · timestamps
"2026-11-20" or "2026-11-20T09:00:00Z" · users, groups, schemas, policies and
clients are addressed by id or unique name · --kebab-case = --camelCase.

Example:
  neko-directory-cli seed
  neko-directory-cli users create --user-name=jane.doe --given-name=Jane --family-name=Doe \
      --emails='[{"value": "jane@example.com"}]' --password=Welcome2026 \
      --extended-attributes='[{"schema": "Enterprise User", "name": "department", "value": "Sales"}]'
  neko-directory-cli users authenticate jane.doe --password=Welcome2026
  neko-directory-cli users set-password jane.doe --password=Spring2027x --must-change-password=true
  neko-directory-cli groups create --display-name=Sales --members='[{"value": "jane.doe"}]'
  neko-directory-cli groups create --display-name=Contractors --group-type=dynamic \
      --membership-rule='userType eq "contractor"'
  neko-directory-cli groups add-member Sales --member=bob
  neko-directory-cli schemas create --urn=urn:acme:schemas:extension:hr:1.0:User --name=HR \
      --attributes='[{"name": "grade", "type": "integer"}]'
  neko-directory-cli password-policies make-default Strong
  neko-directory-cli api-clients create --name=Provisioning --scopes=directory.read,directory.write
  neko-directory-cli api-clients rotate-secret Provisioning
  neko-directory-cli audit-events list --event-type=LOGIN_FAILURE
`;

/// Options that belong to the CLI itself, not to a resource payload.
enum string[] globalOptions = ["tenant", "user", "data-dir", "dataDir", "storage", "json", "help", "file", "yes", "wide"];

/// "workspace-id" → "workspaceId".
string camelCase(string option) pure {
  string result;
  bool upper;
  foreach (c; option) {
    if (c == '-') {
      upper = true;
      continue;
    }
    result ~= upper && c >= 'a' && c <= 'z' ? cast(char)(c - 32) : c;
    upper = false;
  }
  return result;
}

/// The command line adapter.
class DirectoryCli {
  protected ResourceRegistry registry;
  protected DirectoryConfig config;
  protected void delegate(string) @safe output;
  protected RequestIdentity who;
  protected bool json;

  this(ResourceRegistry registry, DirectoryConfig config, void delegate(string) @safe output) {
    this.registry = registry;
    this.config = config;
    this.output = output;
  }

  string usage() {
    return cliUsage.format(registry.adapters.map!(a => a.path).join(" "));
  }

  /// Run one command. Returns the process exit code (0 ok, 1 failure, 2 usage).
  int run(const string[] argv) {
    auto a = CliArgs.parse(argv);
    who.tenantId = TenantId(a.opt("tenant", config.defaultTenant));
    who.userId = UserId(a.opt("user", "cli"));
    who.userName = who.userId.value;
    json = a.flag("json");

    try {
      if (a.positional.length == 0 || a.flag("help") || a.arg(0) == "help") {
        output(usage);
        return a.positional.length == 0 && !a.flag("help") ? 2 : 0;
      }
      switch (a.arg(0)) {
      case "resources":
        return resources();
      case "stats":
        auto s = registry.statistics(who.tenantId);
        return emit(s, detailTable(s).render);
      case "seed":
        auto r = registry.seed(who);
        return emit(r, "%d item(s) created, %d already present\n%s".format(r["created"].get!long,
            r["skipped"].get!long, r["items"].get!(Json[]).map!(c => "  " ~ c.get!string ~ "\n").join));
      case "housekeeping":
        auto r = registry.housekeeping(who.tenantId);
        return emit(r, "%d object(s) examined, %d changed\n%s".format(r["examined"].get!long,
            r["changed"].get!long, r["changes"].get!(Json[]).map!(c => "  " ~ c.get!string ~ "\n").join));
      case "config":
        return emit(config.toJson, config.toJson.toPrettyString ~ "\n");
      default:
        auto adapter = registry.byPath(a.arg(0));
        if (adapter is null)
          throw new CliUsageError("unknown command '" ~ a.arg(0) ~ "'");
        return resource(adapter, a);
      }
    } catch (CliUsageError e) {
      output("error: " ~ e.msg ~ "\nRun 'neko-directory-cli help' for usage.\n");
      return 2;
    } catch (ResourceError e) {
      output("error %d (%s): %s\n".format(e.status, e.code, e.msg));
      return 1;
    } catch (Exception e) {
      output("error: " ~ e.msg ~ "\n");
      return 1;
    }
  }

  // ── commands ───────────────────────────────────────────────────────────

  protected int resources() {
    Table t;
    t.headers = ["Resource", "Title", "Parent", "Actions"];
    foreach (a; registry.adapters)
      t.rows ~= [a.path, a.title, a.parentField, a.actions.map!(x => x.name).join(", ")];
    auto arr = Json.emptyArray;
    foreach (a; registry.adapters)
      arr ~= Json(a.path);
    return emit(arr, t.render);
  }

  protected int resource(IResourceAdapter adapter, CliArgs a) {
    auto verb = a.arg(1);
    switch (verb) {
    case "", "list":
      string[string] filters;
      foreach (k, v; a.options)
        if (!globalOptions.canFind(k))
          filters[camelCase(k)] = v;
      return emitRows(adapter, adapter.list(who.tenantId, filters));
    case "get":
      auto row = adapter.get(who.tenantId, resolveId(adapter, a.requireArg(2, "id or name")));
      return emit(row, detailTable(row).render);
    case "create":
      return emitChange(adapter, "created", adapter.create(who, payload(adapter, a, true)));
    case "update":
      auto id = resolveId(adapter, a.requireArg(2, "id or name"));
      return emitChange(adapter, "updated", adapter.update(who, id, payload(adapter, a, false)));
    case "delete":
      auto id = resolveId(adapter, a.requireArg(2, "id or name"));
      adapter.remove(who, id);
      return emit(Json.emptyObject.set("deleted", id), adapter.typeName ~ " " ~ id ~ " deleted\n");
    case "fields":
      Table t;
      t.headers = ["Field", "Kind", "Options"];
      foreach (f; adapter.inputFields)
        t.rows ~= [f.name, enumText(f.kind) ~ (f.recordType.length ? " (" ~ f.recordType ~ ")" : ""), f.options.join("|")];
      return emit(Json(adapter.inputFields.map!(f => f.name).join(",")), t.render);
    default:
      auto action = adapter.actions.filter!(x => x.name == verb);
      if (action.empty)
        throw new CliUsageError(adapter.path ~ ": unknown verb '" ~ verb ~ "' (actions: "
            ~ adapter.actions.map!(x => x.name).join(", ") ~ ")");
      auto id = resolveId(adapter, a.requireArg(2, "id or name"));
      auto params = Json.emptyObject;
      foreach (k, v; a.options)
        if (action.front.parameters.canFind(camelCase(k)))
          params[camelCase(k)] = v;
      return emitChange(adapter, verb, adapter.invoke(who, id, verb, params));
    }
  }

  // ── input ──────────────────────────────────────────────────────────────

  /// Build the payload from --file and the resource options.
  protected Json payload(IResourceAdapter adapter, CliArgs a, bool creating) {
    auto body = Json.emptyObject;
    if (a.has("file"))
      body = parseJsonString(readFile(a.opt("file")));
    foreach (k, v; a.options) {
      if (globalOptions.canFind(k))
        continue;
      body[camelCase(k)] = v.length > 1 && v[0] == '@' ? readFile(v[1 .. $]) : v;
    }
    auto parent = adapter.parentField;
    if (creating && parent.length > 0 && fieldString(body, parent).length == 0)
      throw new CliUsageError(adapter.path ~ " create needs --" ~ parent);
    return registry.withReferences(who.tenantId, body);
  }

  protected static string readFile(string path) @trusted {
    if (!path.exists)
      throw new CliUsageError("file not found: " ~ path);
    return readText(path);
  }

  protected string resolveId(IResourceAdapter adapter, string idOrName) {
    return registry.resolve(adapter, who.tenantId, idOrName);
  }

  // ── output ─────────────────────────────────────────────────────────────

  protected int emit(Json data, lazy string text) {
    output(json ? data.toPrettyString ~ "\n" : text);
    return 0;
  }

  protected int emitRows(IResourceAdapter adapter, Json[] rows) {
    auto arr = Json.emptyArray;
    foreach (r; rows)
      arr ~= r;
    auto table = tableOf(adapter.columns, rows);
    return emit(arr, table.render ~ "%d %s\n".format(table.length, adapter.path));
  }

  protected int emitChange(IResourceAdapter adapter, string verb, Json row) {
    auto status = fieldString(row, "status");
    auto text = "%s '%s' %s (id %s%s)\n".format(adapter.typeName, displayOf(row), verb,
        fieldString(row, "id"), status.length > 0 ? ", status " ~ status : "");
    // values shown only once (generated secrets) — never stored by the service
    foreach (k, v; row.get!(Json[string]))
      if (k.startsWith(onceAnnotation) && k != onceAnnotation ~ "message")
        text ~= "  %s: %s\n".format(k[onceAnnotation.length .. $], jsonText(v));
    if (row.get!(Json[string]).byKey.any!(k => k == onceAnnotation ~ "clientSecret"))
      text ~= "  (store the secret now — it cannot be shown again)\n";
    return emit(row, text);
  }
}

///
unittest {
  mixin(ShowTest!("DirectoryCli"));

  auto cfg = testConfig("t1");
  string out_;
  auto cli = new DirectoryCli(new ResourceRegistry(buildContainer(cfg).ports), cfg, (s) { out_ ~= s; });

  assert(cli.run([]) == 2);
  assert(cli.run(["seed"]) == 0, out_);
  assert(out_.canFind("4 item(s) created"), out_);
  assert(cli.run(["users", "create", "--user-name=jane.doe", "--given-name=Jane", "--family-name=Doe",
      `--emails=[{"value": "jane@example.com"}]`, "--password=Welcome2026",
      `--extended-attributes=[{"schema": "Enterprise User", "name": "department", "value": "Sales"}]`]) == 0, out_);
  assert(cli.run(["users", "create", "--user-name=bob", "--user-type=contractor"]) == 0, out_);
  assert(cli.run(["users", "create", "--user-name=weak", "--password=x"]) == 1); // policy
  assert(cli.run(["users", "authenticate", "jane.doe", "--password=Welcome2026"]) == 0, out_);
  assert(cli.run(["users", "authenticate", "jane.doe", "--password=wrong"]) == 1);
  assert(cli.run(["groups", "create", "--display-name=Sales", `--members=[{"value": "jane.doe"}]`]) == 0, out_);
  assert(cli.run(["groups", "add-member", "Sales", "--member=bob"]) == 0, out_);
  assert(cli.run(["groups", "create", "--display-name=Contractors", "--group-type=dynamic",
      `--membership-rule=userType eq "contractor"`]) == 0, out_);
  assert(cli.run(["password-policies", "make-default", "Strong"]) == 0, out_);
  out_ = "";
  assert(cli.run(["api-clients", "create", "--name=Provisioning", "--scopes=directory.read,directory.write"]) == 0, out_);
  assert(out_.canFind("clientSecret: ") && out_.canFind("cannot be shown again"), out_);
  out_ = "";
  assert(cli.run(["users", "get", "JANE.DOE", "--json"]) == 0); // by user name, any case
  auto jane = parseJsonString(out_);
  assert(jane["groups"][0].get!string == "Sales" && "passwordHash" !in jane);
  out_ = "";
  assert(cli.run(["groups", "list", "--group-type=dynamic"]) == 0);
  assert(out_.canFind("Contractors") && out_.canFind("1 groups"), out_);
  out_ = "";
  assert(cli.run(["audit-events", "list", "--event-type=LOGIN_FAILURE"]) == 0);
  assert(out_.canFind("1 audit-events"), out_);
  assert(cli.run(["stats"]) == 0);
  assert(cli.run(["housekeeping"]) == 0);
  assert(cli.run(["users", "get", "nope"]) == 1);
  assert(cli.run(["users", "fly", "bob"]) == 2);
  assert(cli.run(["audit-events", "delete", cli.registry.byPath("audit-events").list(TenantId("t1"))[0]["id"].get!string]) == 1);
  assert(camelCase("extended-attributes") == "extendedAttributes");
}
