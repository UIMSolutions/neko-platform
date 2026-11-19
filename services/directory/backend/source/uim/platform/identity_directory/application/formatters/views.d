/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Application-wide formatters: views of the aggregates used for rule evaluation.
module neko.directory.application.formatters.views;

import neko.directory;

mixin(ShowModule!());

@safe:

/// The JSON view of a user that membership rules (SCIM filters) are evaluated
/// against: the payload fields plus SCIM aliases ("name.*", "active",
/// "emails.value", "<schema urn>:<attribute>", "<schema name>.<attribute>").
Json ruleView(const DirectoryUser user, const CustomSchema[] schemas = null) {
  auto j = encode(user, true);
  foreach (secret; ["passwordHash", "passwordHistory"])
    j.remove(secret);
  j["active"] = user.status == UserStatus.active;
  j["name"] = Json.emptyObject
    .set("givenName", user.givenName)
    .set("familyName", user.familyName)
    .set("middleName", user.middleName)
    .set("formatted", fullName(user));
  foreach (ext; user.extendedAttributes) {
    if (ext.schema !in j)
      j[ext.schema] = Json.emptyObject;
    j[ext.schema][ext.name] = ext.value;
    auto schema = schemaFor(schemas, ext.schema);
    if (!schema.isNull) {
      auto alias_ = schema.name.replace(" ", "");
      if (alias_ !in j)
        j[alias_] = Json.emptyObject;
      j[alias_][ext.name] = ext.value;
    }
  }
  return j;
}

/// "User 'jane' created".
string changeText(string kind, string name, string verb) {
  return kind ~ " '" ~ name ~ "' " ~ verb;
}

///
unittest {
  auto u = DirectoryUser(TenantId("t1"));
  u.userName = "jane";
  u.familyName = "Doe";
  u.passwordHash = "secret";
  u.extendedAttributes = [ExtendedAttribute("urn:x:y:User", "costCenter", "4711")];
  auto s = CustomSchema(TenantId("t1"));
  s.urn = "urn:x:y:User";
  s.name = "Enterprise User";
  auto v = ruleView(u, [s]);
  assert("passwordHash" !in v && v["active"].get!bool && v["name"]["familyName"].get!string == "Doe");
  assert(parseScimFilter(`urn:x:y:User:costCenter eq "4711"`).matches(v));
  assert(parseScimFilter(`EnterpriseUser.costCenter eq "4711"`).matches(v));
  assert(changeText("User", "jane", "created") == "User 'jane' created");
}
