/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The resource catalogue of the Identity Directory service: which kinds exist,
/// how they are named per protocol, their table columns, actions, secrets and
/// hidden fields.
module neko.directory.presentation.resources.registry;

import neko.directory;
import neko.directory.presentation.resources.adapter;

mixin(ShowModule!());

@safe:

/// Payload fields that reference another resource (accept an id or a unique
/// name), mapped to the REST path of the referenced resource.
enum string[string] referenceFields = ["passwordPolicy": "password-policies"];

/// Payload fields tried (in order) when a resource is addressed by name.
enum string[] nameFields = ["userName", "displayName", "name", "clientId", "urn", "externalId"];

class ResourceRegistry {
  protected IResourceAdapter[] _adapters;
  DirectoryPorts ports;

  this(DirectoryPorts ports) {
    this.ports = ports;
    auto p = ports;

    _adapters ~= new ResourceAdapter!(DirectoryUser, DirectoryUserId, CreateUserRequest, UpdateUserRequest)(
      p.users, "users", "Users", "User", "Users", "")
      .column("User Name", "userName").column("Display Name", "displayName").column("Type", "userType")
      .column("Status", "status").column("E-Mails", "emails").column("Groups", "groups")
      .column("Last Login", "lastLoginAt").column("ID", "id")
      .hidden("passwordHash").hidden("passwordHistory")
      .action("activate", "Activate", (who, id, _) => p.users.activate(who.tenantId, id, who.userId))
      .action("deactivate", "Deactivate", (who, id, _) => p.users.deactivate(who.tenantId, id, who.userId))
      .action("lock", "Lock", (who, id, _) => p.users.lock(who.tenantId, id, who.userId))
      .action("unlock", "Unlock", (who, id, _) => p.users.unlock(who.tenantId, id, who.userId))
      .action("set-password", "Reset Password", (who, id, x) => p.users.setPassword(who.tenantId, id,
          fieldString(x, "password"), fieldBool(x, "mustChangePassword", true), who.userId), ["password", "mustChangePassword"])
      .action("change-password", "Change Password", (who, id, x) => p.users.changePassword(who.tenantId, id,
          fieldString(x, "currentPassword"), fieldString(x, "newPassword"), who.userId), ["currentPassword", "newPassword"])
      .action("authenticate", "Test Sign-In", (who, id, x) => p.users.authenticate(who.tenantId, id,
          fieldString(x, "password"), fieldString(x, "ipAddress"), who.userId), ["password"]);

    _adapters ~= new ResourceAdapter!(DirectoryGroup, GroupId, CreateGroupRequest, UpdateGroupRequest)(
      p.groups, "groups", "Groups", "Group", "Groups", "")
      .column("Name", "displayName").column("Type", "groupType").column("Members", "members")
      .column("Rule", "membershipRule").column("Description", "description").column("ID", "id")
      .action("add-member", "Add Member", (who, id, x) => p.groups.addMember(who.tenantId, id,
          fieldString(x, "member"), fieldString(x, "memberType"), who.userId), ["member", "memberType"])
      .action("remove-member", "Remove Member", (who, id, x) => p.groups.removeMember(who.tenantId, id,
          fieldString(x, "member"), who.userId), ["member"])
      .action("evaluate", "Evaluate Rule", (who, id, _) => p.groups.evaluate(who.tenantId, id, who.userId));

    _adapters ~= new ResourceAdapter!(CustomSchema, SchemaId, CreateSchemaRequest, UpdateSchemaRequest)(
      p.schemas, "schemas", "Schemas", "Schema", "Schemas", "")
      .column("Name", "name").column("URN", "urn").column("Target", "target").column("Attributes", "attributes")
      .column("Predefined", "predefined").column("ID", "id");

    _adapters ~= new ResourceAdapter!(PasswordPolicy, PasswordPolicyId, CreatePasswordPolicyRequest,
        UpdatePasswordPolicyRequest)(p.passwordPolicies, "password-policies", "PasswordPolicies", "PasswordPolicy",
        "Password Policies", "")
      .column("Name", "name").column("Strength", "strength").column("Min Length", "minLength")
      .column("Expiry (days)", "expiryDays").column("Max Attempts", "maxFailedAttempts").column("Default", "isDefault")
      .column("ID", "id")
      .action("make-default", "Make Default", (who, id, _) => p.passwordPolicies.makeDefault(who.tenantId, id, who.userId));

    _adapters ~= new ResourceAdapter!(ApiClient, ApiClientId, CreateApiClientRequest, UpdateApiClientRequest)(
      p.apiClients, "api-clients", "ApiClients", "ApiClient", "API Clients", "")
      .column("Name", "name").column("Client ID", "clientId").column("Scopes", "scopes").column("Status", "status")
      .column("Expires", "expiresAt").column("Last Used", "lastUsedAt").column("ID", "id")
      .hidden("secretHash")
      .action("rotate-secret", "Rotate Secret", (who, id, _) => p.apiClients.rotateSecret(who.tenantId, id, who.userId))
      .action("revoke", "Revoke", (who, id, _) => p.apiClients.revoke(who.tenantId, id, who.userId))
      .action("reactivate", "Reactivate", (who, id, _) => p.apiClients.reactivate(who.tenantId, id, who.userId))
      .action("verify", "Verify Secret", (who, id, x) => p.apiClients.verify(who.tenantId, id,
          fieldString(x, "secret"), who.userId), ["secret"]);

    _adapters ~= new ResourceAdapter!(AuditEvent, AuditEventId, CreateAuditEventRequest, UpdateAuditEventRequest)(
      p.auditLog, "audit-events", "AuditEvents", "AuditEvent", "Audit Log", "")
      .column("Time", "createdAt").column("Event", "eventType").column("Outcome", "outcome").column("Actor", "actorId")
      .column("Target", "targetName").column("Description", "description").column("ID", "id");
  }

  IResourceAdapter[] adapters() {
    return _adapters;
  }

  /// Adapter by REST path / CLI command (null if unknown).
  IResourceAdapter byPath(string path) {
    foreach (a; _adapters)
      if (a.path == path)
        return a;
    return null;
  }

  /// Adapter by OData entity set (null if unknown).
  IResourceAdapter bySet(string setName) {
    foreach (a; _adapters)
      if (a.setName == setName)
        return a;
    return null;
  }

  /// Adapter owning an OData action name (null if unknown); `action` receives the action.
  IResourceAdapter byODataAction(string odataName, out ResourceAction action) {
    foreach (a; _adapters)
      foreach (act; a.actions)
        if (act.odataName == odataName) {
          action = act;
          return a;
        }
    return null;
  }

  /// An id, or the id of the unique resource of `adapter` with that name (case-insensitive).
  string resolve(IResourceAdapter adapter, TenantId tenantId, string idOrName) {
    if (adapter.get(tenantId, idOrName).type != Json.Type.null_)
      return idOrName;
    auto names = adapter.fields.map!(f => f.name).array;
    auto rows = adapter.list(tenantId);
    foreach (field; nameFields) {
      if (!names.canFind(field))
        continue;
      auto matches = rows.filter!(r => sameName(jsonText(member(r, field)), idOrName)).array;
      if (matches.length == 1)
        return matches[0]["id"].get!string;
      if (matches.length > 1)
        throw new ResourceError(400, "Ambiguous", "'" ~ idOrName ~ "' matches " ~ matches.length.to!string
            ~ " " ~ adapter.path ~ " — use the id");
    }
    throw new ResourceError(404, "NotFound", adapter.typeName ~ " '" ~ idOrName ~ "' not found");
  }

  /// Resolve a reference field: by name references stay names (the use cases resolve them).
  string resolveReference(string field, TenantId tenantId, string idOrName) {
    if (auto target = field in referenceFields)
      if (idOrName.length > 0) {
        auto adapter = byPath(*target);
        auto row = adapter.get(tenantId, resolve(adapter, tenantId, idOrName));
        return fieldString(row, "name", idOrName);
      }
    return idOrName;
  }

  /// A copy of `body` with every reference given by id replaced by its name.
  Json withReferences(TenantId tenantId, Json body) {
    if (body.type != Json.Type.object)
      return body;
    auto result = Json.emptyObject;
    foreach (k, v; body.get!(Json[string]))
      result[k] = (k in referenceFields) !is null && jsonText(v).length > 0
        ? Json(resolveReference(k, tenantId, jsonText(v))) : v;
    return result;
  }

  /// Statistics payload.
  Json statistics(TenantId tenantId) {
    return encode(ports.statistics.statistics(tenantId), true);
  }

  /// Run housekeeping and return the report payload.
  Json housekeeping(TenantId tenantId) {
    return encode(ports.housekeeping.run(tenantId), true);
  }

  /// Install the predefined content and return the report payload.
  Json seed(RequestIdentity who) {
    return encode(ports.seeder.seed(who.tenantId, who.userId), true);
  }
}

///
unittest {
  mixin(ShowTest!("ResourceRegistry"));

  auto registry = new ResourceRegistry(buildContainer(testConfig).ports);
  RequestIdentity who;
  who.tenantId = TenantId("t1");
  who.userId = UserId("admin");
  assert(registry.seed(who)["created"].get!long == 4);
  assert(registry.adapters.length == 6);

  // lenient input; password hashes never leave the service
  auto users = registry.byPath("users");
  assert(!users.fields.any!(f => f.name == "passwordHash" || f.name == "passwordHistory"));
  assert(users.inputFields.any!(f => f.name == "password"));
  auto jane = users.create(who, parseJsonString(`{"userName": "jane", "userType": "partner", "password": "Welcome2026",
    "emails": [{"value": "jane@example.com"}], "extendedAttributes": "[{\"schema\": \"Enterprise User\", \"name\": \"department\", \"value\": \"Sales\"}]"}`));
  assert("passwordHash" !in jane && jane["passwordSet"].get!bool && jane["userType"].get!string == "partner");
  assert(jane["@uim.message"].get!string == "User 'jane' created");
  auto janeId = jane["id"].get!string;
  assert(registry.resolve(users, who.tenantId, "JANE") == janeId); // by user name, any case

  // a PATCH with an empty password keeps the credentials
  auto patched = users.update(who, janeId, parseJsonString(`{"title": "Sales Manager", "passwordPolicy": "strong"}`));
  assert(patched["title"].get!string == "Sales Manager" && patched["passwordPolicy"].get!string == "Strong");
  assert(users.invoke(who, janeId, "authenticate", parseJsonString(`{"password": "Welcome2026"}`))["lastLoginAt"].type == Json.Type.string);

  int status;
  try users.invoke(who, janeId, "authenticate", parseJsonString(`{"password": "nope"}`));
  catch (ResourceError e) status = e.status;
  assert(status == 401);

  // groups by name, members by user name
  auto groups = registry.byPath("groups");
  auto sales = groups.create(who, parseJsonString(`{"displayName": "Sales", "members": [{"value": "jane"}]}`));
  assert(sales["members"][0]["display"].get!string == "jane");
  assert(users.get(who.tenantId, janeId)["groups"][0].get!string == "Sales");
  auto added = groups.invoke(who, sales["id"].get!string, "remove-member", parseJsonString(`{"member": "jane"}`));
  assert(added["members"].length == 0);

  // API client secret: shown once as annotation, hash hidden
  auto clients = registry.byPath("api-clients");
  auto client = clients.create(who, parseJsonString(`{"name": "Provisioning", "scopes": "directory.read, directory.write"}`));
  assert("secretHash" !in client && client["@uim.clientSecret"].get!string.length == 43);
  assert(clients.get(who.tenantId, client["id"].get!string)["@uim.clientSecret"].type == Json.Type.undefined);
  auto rotated = clients.invoke(who, client["id"].get!string, "rotate-secret", Json.emptyObject);
  assert(rotated["@uim.clientSecret"].get!string != client["@uim.clientSecret"].get!string);

  // business errors become ResourceErrors with HTTP status
  status = 0;
  try users.create(who, parseJsonString(`{"userName": "Jane"}`));
  catch (ResourceError e) status = e.status;
  assert(status == 409);
  status = 0;
  try registry.withReferences(who.tenantId, parseJsonString(`{"passwordPolicy": "Nope"}`));
  catch (ResourceError e) status = e.status;
  assert(status == 404);

  ResourceAction act;
  assert(registry.byODataAction("AddMemberGroup", act) is groups && act.parameters == ["member", "memberType"]);
  assert(registry.byPath("audit-events").list(who.tenantId, ["eventType": "LOGIN_FAILURE"]).length == 1);
  assert(registry.statistics(who.tenantId)["users"].get!long == 1);
  assert(registry.bySet("PasswordPolicies").fields.any!(f => f.name == "strength"));
}
