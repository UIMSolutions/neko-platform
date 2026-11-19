/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.manage.schemas;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Interactor: custom schemas. URNs and names are unique; schemas in use
/// cannot be deleted, attributes in use cannot be removed.
class ManageSchemasUseCase
  : ResourceUseCase!(CustomSchema, SchemaId, CreateSchemaRequest, UpdateSchemaRequest),
  IManageSchemasUseCase {

  this(DirectoryRepositories repos, IDirectoryEventPublisher publisher, AuditTrail audit, NowFn clock) {
    super(repos, repos.schemas, publisher, audit, clock, "Schema", "identity.schema",
      AuditKinds(AuditEventType.schemaCreated, AuditEventType.schemaUpdated, AuditEventType.schemaDeleted));
  }

  override protected CustomSchema build(CreateSchemaRequest r) {
    auto schema = CustomSchema(r.tenantId);
    assignMatching(schema, r.spec);
    check(schema);
    return schema;
  }

  override protected void apply(ref CustomSchema schema, SchemaSpec spec) {
    auto before = schema;
    assignMatching(schema, spec);
    check(schema);
    auto values = valuesOf(before);
    if (schema.urn != before.urn || schema.target != before.target)
      ensureState(values.length == 0, "Schema '" ~ before.name ~ "' is in use — its URN and target cannot change");
    foreach (v; values)
      ensureState(schema.attributes.any!(a => a.name == v.name),
        "Attribute '" ~ v.name ~ "' of schema '" ~ before.name ~ "' is in use and cannot be removed");
    foreach (a; schema.attributes)
      if (a.required_ && !before.attributeOf(a.name).required_)
        ensureState(entitiesLacking(before, a.name) == 0, "Attribute '" ~ a.name
            ~ "' cannot become required: objects using schema '" ~ before.name ~ "' have no value");
  }

  protected void check(ref CustomSchema schema) {
    schema.urn = schema.urn.strip;
    schema.name = schema.name.strip;
    validateSchemaDefinition(schema);
    ensureUnique(repo.findByName(schema.tenantId, schema.name), schema);
    auto urn = schema.urn;
    auto id = schema.id;
    ensureState(repo.findMatching(schema.tenantId, (const CustomSchema o) => o.id != id && o.urn == urn).length == 0,
      "Schema URN '" ~ urn ~ "' is already used");
  }

  override protected void beforeRemove(CustomSchema schema) {
    ensureState(!schema.predefined, "Schema '" ~ schema.name ~ "' is predefined and cannot be deleted");
    ensureState(valuesOf(schema).length == 0, "Schema '" ~ schema.name ~ "' is in use");
  }

  /// All extension values of the schema (users and groups).
  protected ExtendedAttribute[] valuesOf(const CustomSchema schema) {
    ExtendedAttribute[] result;
    auto urn = schema.urn;
    foreach (u; repos.users.findByTenant(schema.tenantId))
      result ~= u.extendedAttributes.filter!(x => x.schema == urn).array;
    foreach (g; repos.groups.findByTenant(schema.tenantId))
      result ~= g.extendedAttributes.filter!(x => x.schema == urn).array;
    return result;
  }

  /// Number of users / groups using the schema without a value for `attribute`.
  protected size_t entitiesLacking(const CustomSchema schema, string attribute) {
    auto urn = schema.urn;
    bool lacks(const ExtendedAttribute[] values) {
      return values.any!(x => x.schema == urn) && !values.any!(x => x.schema == urn && sameName(x.name, attribute));
    }

    return repos.users.findMatching(schema.tenantId, (const DirectoryUser u) => lacks(u.extendedAttributes)).length
      + repos.groups.findMatching(schema.tenantId, (const DirectoryGroup g) => lacks(g.extendedAttributes)).length;
  }
}
