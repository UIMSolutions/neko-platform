/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Custom schema rules: definition checks and validation of extension values.
module neko.directory.domain.services.schemas;

import std.ascii : isAlphaNum;
import std.uni : toLower;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Throw a validation exception if a schema definition is inconsistent.
void validateSchemaDefinition(const CustomSchema schema) {
  validate(isUrn(schema.urn), "Schema URN '" ~ schema.urn ~ "' must look like urn:<namespace>:<name>");
  validateDisplayName("Schema name", schema.name, 80);
  validate(schema.attributes.length > 0, "Schema '" ~ schema.name ~ "' needs at least one attribute");
  string[] seen;
  foreach (a; schema.attributes) {
    validate(isAttributeName(a.name), "Attribute name '" ~ a.name ~ "' must start with a letter and contain letters, digits, - or _");
    validate(!seen.any!(s => sameName(s, a.name)), "Attribute '" ~ a.name ~ "' is defined twice");
    seen ~= a.name;
    validate(a.canonicalValues.length == 0 || a.type == AttributeType.string_,
      "Attribute '" ~ a.name ~ "': canonical values are only allowed for string attributes");
    validate(!(a.required_ && a.mutability == Mutability.readOnly),
      "Attribute '" ~ a.name ~ "' cannot be required and read-only");
  }
}

/// True if `value` is a valid literal of an attribute type.
bool isValidValue(AttributeType type, string value) {
  final switch (type) {
  case AttributeType.string_, AttributeType.reference:
    return value.length > 0;
  case AttributeType.boolean:
    return ["true", "false"].canFind(value.toLower);
  case AttributeType.integer:
    try {
      value.to!long;
      return true;
    } catch (Exception)
      return false;
  case AttributeType.decimal:
    try {
      value.to!double;
      return true;
    } catch (Exception)
      return false;
  case AttributeType.dateTime:
    try
      return parseIsoTime(value) > 0;
    catch (Exception)
      return false;
  case AttributeType.binary:
    return value.length % 4 == 0 && value.all!(c => isAlphaNum(c) || c == '+' || c == '/' || c == '=');
  }
}

/// The schema an extension value refers to (by URN or name); CustomSchema.init if none.
const(CustomSchema) schemaFor(const CustomSchema[] schemas, string urnOrName) {
  foreach (ref s; schemas)
    if (s.urn == urnOrName || sameName(s.name, urnOrName))
      return s;
  return CustomSchema.init;
}

/// Validate and normalize extension values of a user or group against the
/// custom schemas of its target: schema references become URNs, attribute
/// names get their defined spelling. `previous` holds the values before an
/// update (read-only and immutable attributes must not change).
ExtendedAttribute[] checkExtensions(const ExtendedAttribute[] values, const CustomSchema[] schemas,
    SchemaTarget target, const ExtendedAttribute[] previous = null) {
  ExtendedAttribute[] result;
  string[] errors;
  foreach (v; values) {
    if (v.value.length == 0)
      continue;
    auto schema = schemaFor(schemas, v.schema);
    if (schema.isNull) {
      errors ~= "unknown schema '" ~ v.schema ~ "'";
      continue;
    }
    if (schema.target != target) {
      errors ~= "schema '" ~ schema.name ~ "' does not extend " ~ enumText(target) ~ "s";
      continue;
    }
    auto def = schema.attributeOf(v.name);
    if (def.name.length == 0) {
      errors ~= "schema '" ~ schema.name ~ "' has no attribute '" ~ v.name ~ "'";
      continue;
    }
    if (!isValidValue(def.type, v.value))
      errors ~= def.name ~ " '" ~ v.value ~ "' is not a valid " ~ enumText(def.type);
    if (def.canonicalValues.length > 0 && !def.canonicalValues.any!(c => def.caseExact ? c == v.value : sameName(c, v.value)))
      errors ~= def.name ~ " must be one of " ~ def.canonicalValues.join(", ");
    if (!def.multiValued && result.any!(r => r.schema == schema.urn && r.name == def.name))
      errors ~= def.name ~ " is single-valued";
    result ~= ExtendedAttribute(schema.urn, def.name, v.value);
  }

  // required, read-only and immutable attributes
  foreach (schema; schemas) {
    if (schema.target != target)
      continue;
    bool used = result.any!(r => r.schema == schema.urn);
    foreach (def; schema.attributes) {
      auto now = result.filter!(r => r.schema == schema.urn && r.name == def.name).map!(r => r.value).array;
      auto before = previous.filter!(r => (r.schema == schema.urn || sameName(r.schema, schema.name)) && sameName(r.name, def.name))
        .map!(r => r.value).array;
      if (def.required_ && used && now.length == 0)
        errors ~= schema.name ~ "." ~ def.name ~ " is required";
      if (def.mutability == Mutability.readOnly && now != before)
        errors ~= schema.name ~ "." ~ def.name ~ " is read-only";
      if (def.mutability == Mutability.immutable_ && before.length > 0 && now != before)
        errors ~= schema.name ~ "." ~ def.name ~ " cannot be changed once set";
    }
  }
  validate(errors.length == 0, "Invalid extension attributes: " ~ errors.join("; "));
  return result;
}

///
unittest {
  auto ent = CustomSchema(TenantId("t1"));
  ent.urn = "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User";
  ent.name = "Enterprise User";
  ent.attributes = [SchemaAttribute("employeeNumber", "", AttributeType.string_, false, true),
    SchemaAttribute("costCenter", "", AttributeType.integer),
    SchemaAttribute("division", "", AttributeType.string_, false, false, false, Mutability.readWrite,
      Returned.default_, Uniqueness.none, ["Sales", "R&D"])];
  validateSchemaDefinition(ent);

  auto ok = checkExtensions([ExtendedAttribute("Enterprise User", "EMPLOYEENUMBER", "4711"),
      ExtendedAttribute(ent.urn, "division", "sales")], [ent], SchemaTarget.user);
  assert(ok.length == 2 && ok[0].schema == ent.urn && ok[0].name == "employeeNumber");

  bool fails(const ExtendedAttribute[] values) {
    try
      checkExtensions(values, [ent], SchemaTarget.user);
    catch (DirectoryValidationException)
      return true;
    return false;
  }

  assert(fails([ExtendedAttribute(ent.urn, "costCenter", "x1")])); // integer + employeeNumber missing
  assert(fails([ExtendedAttribute(ent.urn, "employeeNumber", "1"), ExtendedAttribute(ent.urn, "division", "HR")]));
  assert(fails([ExtendedAttribute("Nope", "a", "b")]));
  assert(checkExtensions(null, [ent], SchemaTarget.user).length == 0); // schema not used: nothing required

  assert(isValidValue(AttributeType.dateTime, "2026-11-20") && !isValidValue(AttributeType.dateTime, "x"));
  assert(isValidValue(AttributeType.boolean, "TRUE") && isValidValue(AttributeType.binary, "aGk="));
}
