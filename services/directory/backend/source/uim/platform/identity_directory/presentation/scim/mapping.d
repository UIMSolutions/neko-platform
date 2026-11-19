/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Mapping between the service payloads and SCIM 2.0 resources (RFC 7643),
/// plus the SCIM PATCH engine (RFC 7644 section 3.5.2).
module neko.directory.presentation.scim.mapping;

import std.uni : icmp;
import neko.directory.helpers.json : mergeObjects = mergeJson;
import neko.directory;

mixin(ShowModule!());

@safe:

enum scimUserSchema = "urn:ietf:params:scim:schemas:core:2.0:User";
enum scimGroupSchema = "urn:ietf:params:scim:schemas:core:2.0:Group";
/// Directory specific group attributes (description, groupType, membershipRule).
enum scimDirectoryGroupSchema = "urn:uim:params:scim:schemas:extension:directory:1.0:Group";
/// Directory specific user attributes (status, sign-in state, password policy).
enum scimDirectoryUserSchema = "urn:uim:params:scim:schemas:extension:directory:1.0:User";
enum scimListSchema = "urn:ietf:params:scim:api:messages:2.0:ListResponse";
enum scimPatchSchema = "urn:ietf:params:scim:api:messages:2.0:PatchOp";
enum scimErrorSchema = "urn:ietf:params:scim:api:messages:2.0:Error";
enum scimSearchSchema = "urn:ietf:params:scim:api:messages:2.0:SearchRequest";

private enum string[] userStrings = ["externalId", "userName", "displayName", "nickName", "profileUrl", "title",
    "userType", "preferredLanguage", "locale", "timezone"];
private enum string[] nameParts = ["givenName", "familyName", "middleName", "honorificPrefix", "honorificSuffix"];
private enum string[] userLists = ["emails", "phoneNumbers", "addresses"];

/// Attribute definitions of the custom schemas: urn → name → (type, multiValued).
struct SchemaCatalog {
  Json[string] attributes; /// urn → { name: attribute row }
  string[string] targets; /// urn → "user" / "group"

  static SchemaCatalog of(const Json[] schemaRows) {
    SchemaCatalog c;
    foreach (row; schemaRows) {
      auto urn = fieldString(row, "urn");
      auto defs = Json.emptyObject;
      foreach (a; member(row, "attributes").type == Json.Type.array ? row["attributes"].get!(Json[]) : null)
        defs[fieldString(a, "name")] = a;
      c.attributes[urn] = defs;
      c.targets[urn] = fieldString(row, "target");
    }
    return c;
  }

  Json definition(string urn, string name) const {
    if (auto defs = urn in attributes)
      foreach (k, v; (*defs).get!(Json[string]))
        if (icmp(k, name) == 0)
          return v;
    return Json.undefined;
  }
}

/// A key of an object, compared case-insensitively ("" if missing).
string keyOf(Json obj, string name) {
  if (obj.type == Json.Type.object)
    foreach (k, _; obj.get!(Json[string]))
      if (icmp(k, name) == 0)
        return k;
  return "";
}

/// Field of an object, case-insensitive.
Json fieldOf(Json obj, string name) {
  auto k = keyOf(obj, name);
  return k.length ? obj[k] : Json.undefined;
}

private Json typed(string value, string type) {
  try {
    switch (type) {
    case "integer":
      return Json(value.to!long);
    case "decimal":
      return Json(value.to!double);
    case "boolean":
      return Json(value.toLower == "true");
    default:
      return Json(value);
    }
  } catch (Exception)
    return Json(value);
}

private Json meta(Json payload, string resourceType, string location) {
  return Json.emptyObject
    .set("resourceType", resourceType)
    .set("created", fieldString(payload, "createdAt"))
    .set("lastModified", fieldString(payload, "updatedAt"))
    .set("location", location)
    .set("version", `W/"` ~ fieldString(payload, "updatedAt") ~ `"`);
}

/// Extension objects ("urn:...": {attr: value}) of extendedAttributes rows.
private void addExtensions(ref Json scim, Json payload, const SchemaCatalog catalog) {
  auto values = member(payload, "extendedAttributes");
  if (values.type != Json.Type.array)
    return;
  foreach (v; values.get!(Json[])) {
    auto urn = fieldString(v, "schema");
    auto name = fieldString(v, "name");
    auto def = catalog.definition(urn, name);
    auto value = typed(fieldString(v, "value"), fieldString(def, "type"));
    if (urn !in scim) {
      scim[urn] = Json.emptyObject;
      scim["schemas"] ~= Json(urn);
    }
    if (fieldBool(def, "multiValued")) {
      if (name !in scim[urn])
        scim[urn][name] = Json.emptyArray;
      scim[urn][name] ~= value;
    } else
      scim[urn][name] = value;
  }
}

/// extendedAttributes rows of the extension objects of a SCIM resource.
private Json readExtensions(Json scim, string[] ignore) {
  auto result = Json.emptyArray;
  foreach (k, v; scim.get!(Json[string])) {
    if (!k.startsWith("urn:") || ignore.any!(i => icmp(i, k) == 0) || v.type != Json.Type.object)
      continue;
    foreach (name, value; v.get!(Json[string])) {
      auto items = value.type == Json.Type.array ? value.get!(Json[]) : [value];
      foreach (item; items)
        if (item.type != Json.Type.null_ && jsonText(item).length > 0)
          result ~= Json.emptyObject.set("schema", k).set("name", name).set("value", jsonText(item));
    }
  }
  return result;
}

/// SCIM user resource of a user payload. `groupIds` maps group display names to ids.
Json userToScim(Json payload, string baseUrl, const SchemaCatalog catalog, string[string] groupIds) {
  auto id = fieldString(payload, "id");
  auto scim = Json.emptyObject;
  scim["schemas"] = Json([Json(scimUserSchema)]);
  scim["id"] = id;
  foreach (key; userStrings)
    if (fieldString(payload, key).length > 0)
      scim[key] = fieldString(payload, key);
  auto name = Json.emptyObject;
  foreach (part; nameParts)
    if (fieldString(payload, part).length > 0)
      name[part] = fieldString(payload, part);
  auto formatted = nameParts[0 .. 3].map!(p => fieldString(payload, p)).filter!(s => s.length > 0).join(" ");
  if (formatted.length > 0)
    name["formatted"] = formatted;
  scim["name"] = name;
  scim["active"] = fieldString(payload, "status") == "active";
  foreach (key; userLists)
    if (member(payload, key).type == Json.Type.array && payload[key].length > 0)
      scim[key] = payload[key];
  auto groups = Json.emptyArray;
  foreach (kind; ["groups", "inheritedGroups"])
    foreach (g; fieldStrings(payload, kind))
      groups ~= Json.emptyObject
        .set("value", groupIds.get(g, ""))
        .set("display", g)
        .set("type", kind == "groups" ? "direct" : "indirect")
        .set("$ref", baseUrl ~ "/Groups/" ~ groupIds.get(g, ""));
  if (groups.length > 0)
    scim["groups"] = groups;
  addExtensions(scim, payload, catalog);
  scim["schemas"] ~= Json(scimDirectoryUserSchema);
  scim[scimDirectoryUserSchema] = Json.emptyObject
    .set("status", fieldString(payload, "status"))
    .set("passwordPolicy", fieldString(payload, "passwordPolicy"))
    .set("mustChangePassword", fieldBool(payload, "mustChangePassword"))
    .set("lastLoginAt", fieldString(payload, "lastLoginAt"));
  scim["meta"] = meta(payload, "User", baseUrl ~ "/Users/" ~ id);
  return scim;
}

/// Service payload of a SCIM user. `full` (PUT) clears attributes that are missing.
Json scimToUser(Json scim, bool full) {
  validate(scim.type == Json.Type.object, "SCIM resource must be a JSON object");
  auto p = Json.emptyObject;
  foreach (key; userStrings) {
    auto v = fieldOf(scim, key);
    if (v.type != Json.Type.undefined)
      p[key] = jsonText(v);
    else if (full && key != "userType" && key != "preferredLanguage")
      p[key] = "";
  }
  auto name = fieldOf(scim, "name");
  foreach (part; nameParts) {
    auto v = fieldOf(name, part);
    if (v.type != Json.Type.undefined)
      p[part] = jsonText(v);
    else if (full)
      p[part] = "";
  }
  foreach (key; userLists) {
    auto v = fieldOf(scim, key);
    if (v.type == Json.Type.array)
      p[key] = v;
    else if (full)
      p[key] = Json.emptyArray;
  }
  auto directory = fieldOf(scim, scimDirectoryUserSchema);
  auto active = fieldOf(scim, "active");
  if (active.type != Json.Type.undefined)
    p["status"] = jsonBool(active, true) ? "active" : "inactive";
  else if (fieldString(directory, "status").length > 0)
    p["status"] = fieldString(directory, "status");
  if (fieldString(directory, "status") == "locked" || fieldString(directory, "status") == "staged")
    p["status"] = fieldString(directory, "status");
  if (fieldOf(directory, "passwordPolicy").type != Json.Type.undefined)
    p["passwordPolicy"] = jsonText(fieldOf(directory, "passwordPolicy"));
  auto password = fieldOf(scim, "password");
  if (password.type == Json.Type.string)
    p["password"] = password.get!string;
  auto ext = readExtensions(scim, [scimUserSchema, scimDirectoryUserSchema]);
  if (ext.length > 0 || full)
    p["extendedAttributes"] = ext;
  return p;
}

/// SCIM group resource of a group payload.
Json groupToScim(Json payload, string baseUrl, const SchemaCatalog catalog) {
  auto id = fieldString(payload, "id");
  auto scim = Json.emptyObject;
  scim["schemas"] = Json([Json(scimGroupSchema)]);
  scim["id"] = id;
  scim["displayName"] = fieldString(payload, "displayName");
  if (fieldString(payload, "externalId").length > 0)
    scim["externalId"] = fieldString(payload, "externalId");
  auto members = Json.emptyArray;
  if (member(payload, "members").type == Json.Type.array)
    foreach (m; payload["members"].get!(Json[])) {
      auto isGroup = fieldString(m, "type") == "group";
      members ~= Json.emptyObject
        .set("value", fieldString(m, "value"))
        .set("display", fieldString(m, "display"))
        .set("type", isGroup ? "Group" : "User")
        .set("$ref", baseUrl ~ (isGroup ? "/Groups/" : "/Users/") ~ fieldString(m, "value"));
    }
  scim["members"] = members;
  addExtensions(scim, payload, catalog);
  scim["schemas"] ~= Json(scimDirectoryGroupSchema);
  scim[scimDirectoryGroupSchema] = Json.emptyObject
    .set("description", fieldString(payload, "description"))
    .set("groupType", fieldString(payload, "groupType"))
    .set("membershipRule", fieldString(payload, "membershipRule"));
  scim["meta"] = meta(payload, "Group", baseUrl ~ "/Groups/" ~ id);
  return scim;
}

/// Service payload of a SCIM group.
Json scimToGroup(Json scim, bool full) {
  validate(scim.type == Json.Type.object, "SCIM resource must be a JSON object");
  auto p = Json.emptyObject;
  foreach (key; ["displayName", "externalId"]) {
    auto v = fieldOf(scim, key);
    if (v.type != Json.Type.undefined)
      p[key] = jsonText(v);
    else if (full && key == "externalId")
      p[key] = "";
  }
  auto members = fieldOf(scim, "members");
  if (members.type == Json.Type.array) {
    auto list = Json.emptyArray;
    foreach (m; members.get!(Json[]))
      list ~= Json.emptyObject
        .set("value", jsonText(fieldOf(m, "value")))
        .set("type", jsonText(fieldOf(m, "type")).toLower == "group" ? "group" : "user");
    p["members"] = list;
  } else if (full)
    p["members"] = Json.emptyArray;
  auto directory = fieldOf(scim, scimDirectoryGroupSchema);
  foreach (key; ["description", "groupType", "membershipRule"]) {
    auto v = fieldOf(directory, key);
    if (v.type != Json.Type.undefined)
      p[key] = jsonText(v);
  }
  auto ext = readExtensions(scim, [scimGroupSchema, scimDirectoryGroupSchema]);
  if (ext.length > 0 || full)
    p["extendedAttributes"] = ext;
  return p;
}

// ─────────────────────────────────────────────────────────────────────────────
// PATCH
// ─────────────────────────────────────────────────────────────────────────────

/// A parsed PATCH path: [urn:]attribute[[filter]][.sub]
struct PatchPath {
  string container; /// URN or parent attribute ("name"), "" = top level
  string attribute;
  string filter;
  string sub;

  static PatchPath parse(string path) {
    PatchPath p;
    auto rest = path.strip;
    validate(rest.length > 0, "Empty PATCH path");
    if (rest.startsWith("urn:")) {
      auto open = rest.indexOf('[');
      auto head = open < 0 ? rest : rest[0 .. open];
      auto colon = head.lastIndexOf(':');
      p.container = rest[0 .. colon];
      rest = rest[colon + 1 .. $];
    }
    auto open = rest.indexOf('[');
    if (open >= 0) {
      auto close = rest.lastIndexOf(']');
      validate(close > open, "Invalid PATCH path '" ~ path ~ "'");
      p.attribute = rest[0 .. open];
      p.filter = rest[open + 1 .. close];
      if (close + 1 < rest.length) {
        validate(rest[close + 1] == '.', "Invalid PATCH path '" ~ path ~ "'");
        p.sub = rest[close + 2 .. $];
      }
    } else {
      auto dot = rest.indexOf('.');
      if (dot > 0 && p.container.length == 0) {
        p.container = rest[0 .. dot];
        p.attribute = rest[dot + 1 .. $];
      } else
        p.attribute = rest;
    }
    validate(p.attribute.length > 0, "Invalid PATCH path '" ~ path ~ "'");
    return p;
  }
}

/// Apply SCIM PATCH operations to a SCIM resource (in place) and return it.
Json applyPatch(Json resource, Json patch) {
  validate(patch.type == Json.Type.object, "PATCH body must be a JSON object");
  auto ops = fieldOf(patch, "Operations");
  validate(ops.type == Json.Type.array && ops.length > 0, "PATCH needs a non-empty 'Operations' array");
  foreach (op; ops.get!(Json[]))
    applyOperation(resource, jsonText(fieldOf(op, "op")).toLower, jsonText(fieldOf(op, "path")), fieldOf(op, "value"));
  return resource;
}

private void applyOperation(ref Json doc, string op, string path, Json value) {
  validate(["add", "replace", "remove"].canFind(op), "Unknown PATCH op '" ~ op ~ "'");
  if (path.length == 0) {
    validate(op != "remove", "remove needs a path");
    validate(value.type == Json.Type.object, op ~ " without path needs an object value");
    foreach (k, v; value.get!(Json[string])) {
      if (k.startsWith("urn:") && v.type == Json.Type.object) {
        foreach (sk, sv; v.get!(Json[string]))
          applyOperation(doc, op, k ~ ":" ~ sk, sv);
      } else if (icmp(k, "name") == 0 && v.type == Json.Type.object) {
        foreach (sk, sv; v.get!(Json[string]))
          applyOperation(doc, op, "name." ~ sk, sv);
      } else
        applyOperation(doc, op, k, v);
    }
    return;
  }

  auto p = PatchPath.parse(path);
  // the object holding the attribute: the resource, an extension ("urn:...") or a complex attribute ("name")
  string containerKey;
  Json target = doc;
  if (p.container.length > 0) {
    containerKey = keyOf(doc, p.container);
    if (containerKey.length == 0) {
      if (op == "remove")
        return;
      containerKey = p.container;
      doc[containerKey] = Json.emptyObject;
      if (p.container.startsWith("urn:") && "schemas" in doc && doc["schemas"].type == Json.Type.array)
        doc["schemas"] ~= Json(p.container);
    }
    target = doc[containerKey];
  }
  applyToAttribute(target, op, p, value);
  if (p.container.length > 0)
    doc[containerKey] = target;
  else
    doc = target;
}

private void applyToAttribute(ref Json target, string op, const PatchPath p, Json value) {
  auto key = keyOf(target, p.attribute);
  if (key.length == 0)
    key = p.attribute;
  auto current = key in target ? target[key] : Json.undefined;

  if (p.filter.length > 0) {
    auto filter = parseScimFilter(p.filter);
    validate(current.type == Json.Type.array || op == "add", "Attribute '" ~ p.attribute ~ "' is not multi-valued");
    Json[] items = current.type == Json.Type.array ? current.get!(Json[]) : null;
    Json[] result;
    foreach (item; items) {
      if (!filter.matches(item)) {
        result ~= item;
        continue;
      }
      if (op == "remove") {
        if (p.sub.length > 0) {
          auto sk = keyOf(item, p.sub);
          if (sk.length)
            item.remove(sk);
          result ~= item;
        }
      } else if (p.sub.length > 0) {
        auto sk = keyOf(item, p.sub);
        item[sk.length ? sk : p.sub] = value;
        result ~= item;
      } else
        result ~= value.type == Json.Type.object ? mergeObjects(item, value) : value;
    }
    target[key] = Json(result);
    return;
  }

  switch (op) {
  case "add":
    if (current.type == Json.Type.array || value.type == Json.Type.array) {
      Json[] items = current.type == Json.Type.array ? current.get!(Json[]) : null;
      foreach (v; value.type == Json.Type.array ? value.get!(Json[]) : [value]) {
        auto id = jsonText(fieldOf(v, "value"));
        if (!items.any!(i => id.length > 0 && jsonText(fieldOf(i, "value")) == id))
          items ~= v;
      }
      target[key] = Json(items);
    } else if (current.type == Json.Type.object && value.type == Json.Type.object)
      target[key] = mergeObjects(current, value);
    else
      target[key] = value;
    break;
  case "replace":
    target[key] = current.type == Json.Type.object && value.type == Json.Type.object ? mergeObjects(current, value) : value;
    break;
  default: // remove
    if (current.type == Json.Type.array && value.type == Json.Type.array) {
      // Azure AD style: remove the listed members
      auto drop = value.get!(Json[]).map!(v => jsonText(fieldOf(v, "value"))).array;
      target[key] = Json(current.get!(Json[]).filter!(i => !drop.canFind(jsonText(fieldOf(i, "value")))).array);
    } else if (key in target)
      target.remove(key);
    break;
  }
}

///
unittest {
  mixin(ShowTest!("SCIM mapping"));

  auto catalog = SchemaCatalog.of([parseJsonString(`{"urn": "urn:x:enterprise:2.0:User", "target": "user",
    "attributes": [{"name": "costCenter", "type": "integer"}, {"name": "skills", "type": "string", "multiValued": true}]}`)]);
  auto payload = parseJsonString(`{"id": "u1", "userName": "jane", "givenName": "Jane", "familyName": "Doe",
    "status": "active", "emails": [{"value": "jane@example.com", "type": "work", "primary": true}],
    "groups": ["Sales"], "inheritedGroups": ["EMEA"], "createdAt": "2026-11-18T10:00:00Z", "updatedAt": "2026-11-18T10:00:00Z",
    "extendedAttributes": [{"schema": "urn:x:enterprise:2.0:User", "name": "costCenter", "value": "4711"},
      {"schema": "urn:x:enterprise:2.0:User", "name": "skills", "value": "D"},
      {"schema": "urn:x:enterprise:2.0:User", "name": "skills", "value": "SCIM"}]}`);
  auto scim = userToScim(payload, "/scim/v2", catalog, ["Sales": "g1", "EMEA": "g2"]);
  assert(scim["name"]["formatted"].get!string == "Jane Doe" && scim["active"].get!bool);
  assert(scim["urn:x:enterprise:2.0:User"]["costCenter"].get!long == 4711);
  assert(scim["urn:x:enterprise:2.0:User"]["skills"].length == 2);
  assert(scim["groups"][1]["type"].get!string == "indirect" && scim["groups"][0]["value"].get!string == "g1");
  assert(scim["meta"]["location"].get!string == "/scim/v2/Users/u1");
  assert(parseScimFilter(`emails[type eq "work"] and urn:x:enterprise:2.0:User:costCenter eq 4711`).matches(scim));

  auto back = scimToUser(scim, true);
  assert(back["userName"].get!string == "jane" && back["givenName"].get!string == "Jane" && back["status"].get!string == "active");
  assert(back["extendedAttributes"].length == 3 && back["nickName"].get!string == "");

  // PATCH: Azure AD / Okta style operations
  auto patched = applyPatch(scim.clone, parseJsonString(`{"schemas": ["` ~ scimPatchSchema ~ `"], "Operations": [
    {"op": "replace", "path": "active", "value": false},
    {"op": "replace", "path": "name.familyName", "value": "Smith"},
    {"op": "add", "path": "emails", "value": [{"value": "j@home.io", "type": "home"}]},
    {"op": "replace", "path": "emails[type eq \"work\"].value", "value": "jane@acme.io"},
    {"op": "add", "path": "urn:x:enterprise:2.0:User:costCenter", "value": 99},
    {"op": "replace", "value": {"title": "Lead", "urn:x:enterprise:2.0:User": {"skills": ["D"]}}}]}`));
  auto u = scimToUser(patched, true);
  assert(u["status"].get!string == "inactive" && u["familyName"].get!string == "Smith" && u["title"].get!string == "Lead");
  assert(u["emails"].length == 2 && u["emails"][0]["value"].get!string == "jane@acme.io");
  assert(u["extendedAttributes"].length == 2); // costCenter 99, skills D
  auto removed = applyPatch(patched, parseJsonString(`{"Operations": [{"op": "remove", "path": "emails[type eq \"home\"]"},
    {"op": "remove", "path": "title"}]}`));
  assert(removed["emails"].length == 1 && "title" !in removed);

  auto group = groupToScim(parseJsonString(`{"id": "g1", "displayName": "Sales", "groupType": "nested",
    "members": [{"value": "u1", "type": "user", "display": "jane"}, {"value": "g2", "type": "group", "display": "EMEA"}]}`), "/scim/v2", catalog);
  assert(group["members"][1]["type"].get!string == "Group" && group[scimDirectoryGroupSchema]["groupType"].get!string == "nested");
  auto g = applyPatch(group, parseJsonString(`{"Operations": [{"op": "add", "path": "members", "value": [{"value": "u2"}]},
    {"op": "remove", "path": "members[value eq \"u1\"]"}, {"op": "remove", "path": "members", "value": [{"value": "g2"}]}]}`));
  auto gp = scimToGroup(g, true);
  assert(gp["members"].length == 1 && gp["members"][0]["value"].get!string == "u2" && gp["groupType"].get!string == "nested");

  auto pp = PatchPath.parse(`urn:x:enterprise:2.0:User:costCenter`);
  assert(pp.container == "urn:x:enterprise:2.0:User" && pp.attribute == "costCenter");
  pp = PatchPath.parse(`emails[type eq "work"].value`);
  assert(pp.attribute == "emails" && pp.filter == `type eq "work"` && pp.sub == "value");
}
