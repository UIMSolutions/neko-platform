/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.persistence.mappers.record;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Generic mapper between entities and database records, driven by
/// compile-time reflection (see helpers.codec). Records keep timestamps as raw
/// std-time numbers and enums by name; unknown or missing fields fall back to
/// the entity defaults, so older snapshots stay readable.
struct RecordMapper(TEntity) {
  static Json toRecord(const TEntity entity) {
    return encode(entity, false);
  }

  static TEntity fromRecord(Json record) {
    return decode!TEntity(record);
  }
}

///
unittest {
  mixin(ShowTest!("RecordMapper"));

  auto u = DirectoryUser(TenantId("t1"));
  u.userName = "jane";
  u.userType = UserType.public_;
  u.emails = [Email("jane@example.com", "work", true)];
  u.extendedAttributes = [ExtendedAttribute("urn:x:y:User", "costCenter", "4711")];
  u.passwordHistory = ["h1", "h2"];
  auto record = RecordMapper!DirectoryUser.toRecord(u);
  assert(record["userType"].get!string == "public" && record["emails"][0]["primary"].get!bool);
  assert(record["createdAt"].type == Json.Type.int_);
  assert(RecordMapper!DirectoryUser.fromRecord(record) == u);

  auto s = CustomSchema(TenantId("t1"));
  s.attributes = [SchemaAttribute("division", "", AttributeType.string_, false, true, false, Mutability.immutable_,
    Returned.default_, Uniqueness.server, ["Sales"])];
  auto sr = RecordMapper!CustomSchema.toRecord(s);
  assert(sr["attributes"][0]["required"].get!bool && sr["attributes"][0]["type"].get!string == "string");
  assert(sr["attributes"][0]["mutability"].get!string == "immutable");
  assert(RecordMapper!CustomSchema.fromRecord(sr) == s);

  auto e = AuditEvent(TenantId("t1"));
  e.eventType = AuditEventType.loginFailure;
  e.details = [KeyValue("ipAddress", "10.0.0.1")];
  auto er = RecordMapper!AuditEvent.toRecord(e);
  assert(er["eventType"].get!string == "LOGIN_FAILURE");
  assert(RecordMapper!AuditEvent.fromRecord(er) == e);
}
