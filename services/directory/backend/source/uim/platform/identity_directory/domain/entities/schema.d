/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.entities.schema;

import neko.directory;

mixin(ShowModule!());

@safe:

/// A custom schema extending users or groups with additional attributes
/// (SCIM schema extension, e.g. "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User").
struct CustomSchema {
  mixin TenantEntity!SchemaId;

  string urn; /// unique schema URN (SCIM schema id)
  string name; /// unique short name
  string description;
  SchemaTarget target = SchemaTarget.user;
  SchemaAttribute[] attributes;
  /// Installed by the seed service; cannot be deleted.
  bool predefined;
}

/// Attribute definition by name (case-insensitive); SchemaAttribute.init if unknown.
const(SchemaAttribute) attributeOf(const CustomSchema schema, string name) {
  foreach (a; schema.attributes)
    if (sameName(a.name, name))
      return a;
  return SchemaAttribute.init;
}

///
unittest {
  auto s = CustomSchema(TenantId("t1"));
  s.attributes = [SchemaAttribute("costCenter")];
  assert(s.attributeOf("COSTCENTER").name == "costCenter");
  assert(s.attributeOf("nope").name.length == 0);
}
