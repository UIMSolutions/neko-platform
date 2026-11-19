/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Value objects embedded in the aggregates (exchanged as OData complex types
/// and SCIM multi-valued attributes).
module neko.directory.domain.types.values;

import neko.directory;

mixin(ShowModule!());

@safe:

/// An ordered key/value pair (audit details).
struct KeyValue {
  string key;
  string value;
}

/// SCIM "emails" entry.
struct Email {
  string value;
  string type = "work"; /// work | home | other
  bool primary;
}

/// SCIM "phoneNumbers" entry.
struct PhoneNumber {
  string value;
  string type = "work"; /// work | mobile | home | fax | other
  bool primary;
}

/// SCIM "addresses" entry.
struct PostalAddress {
  string formatted;
  string streetAddress;
  string locality;
  string region;
  string postalCode;
  string country;
  string type = "work"; /// work | home | other
  bool primary;
}

/// Value of an attribute defined by a custom schema (SCIM schema extension).
/// `schema` holds the schema URN (a schema name is accepted on input).
struct ExtendedAttribute {
  string schema;
  string name;
  string value;
}

/// Direct member of a group: a user or (nested groups) another group.
struct GroupMember {
  string value; /// id of the user or group
  MemberType type = MemberType.user;
  string display; /// userName or group display name
}

/// Attribute definition of a custom schema (RFC 7643 section 7).
struct SchemaAttribute {
  string name;
  string description;
  AttributeType type = AttributeType.string_;
  bool multiValued;
  bool required_; /// "required"
  bool caseExact;
  Mutability mutability = Mutability.readWrite;
  Returned returned = Returned.default_;
  Uniqueness uniqueness = Uniqueness.none;
  string[] canonicalValues;
}

/// Value of `key` in a list of pairs ("" if missing).
string valueOf(const KeyValue[] pairs, string key) {
  foreach (p; pairs)
    if (p.key == key)
      return p.value;
  return "";
}

///
unittest {
  assert(valueOf([KeyValue("ip", "10.0.0.1")], "ip") == "10.0.0.1");
  assert(valueOf([KeyValue("ip", "10.0.0.1")], "x") == "");
}
