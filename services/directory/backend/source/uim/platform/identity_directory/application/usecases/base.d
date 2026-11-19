/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.base;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Successful result.
UsecaseResult succeeded(string id, string message = "OK", Json data = Json.emptyObject) {
  return UsecaseResult(true, id, message, 200, data);
}

/// Run `action` and map business exceptions to a failed UsecaseResult whose
/// `code` is the exception status (401, 404, 409, 422).
UsecaseResult guarded(scope UsecaseResult delegate() @safe action) {
  try
    return action();
  catch (DirectoryException e)
    return UsecaseResult(false, "", e.msg, e.status);
}

/// "API client" → "ApiClient", "Password policy" → "PasswordPolicy".
string targetTypeOf(string kindLabel) pure {
  string result;
  foreach (word; kindLabel.split(" "))
    if (word.length > 0)
      result ~= word[0 .. 1].toUpper ~ word[1 .. $].toLower;
  return result;
}

/// What the audit log records for the standard changes of an aggregate.
struct AuditKinds {
  AuditEventType created;
  AuditEventType updated;
  AuditEventType deleted;
}

/// Base class of the aggregate interactors (common behaviour: result mapping,
/// uniqueness checks, event publishing and the audit trail).
///
/// Subclasses supply `TEntity build(TCreate)` (validated, not yet saved) and
/// `void apply(ref TEntity, TSpec)`; optionally `beforeRemove` (dependency
/// checks), `afterChange` (consistency of other aggregates), `afterRemove`
/// (cascades) and `createdData` (values returned once).
abstract class ResourceUseCase(TEntity, TId, TCreate, TUpdate) : IManageResource!(TEntity, TId, TCreate, TUpdate) {
  alias TSpec = typeof(TUpdate.init.spec);

  protected DirectoryRepositories repos;
  protected IDirectoryEventPublisher publisher;
  protected AuditTrail audit;
  protected IDirectoryRepository!(TEntity, TId) repo;
  protected NowFn clock;
  protected string kindLabel; /// "User"
  protected string topic; /// "identity.user"
  protected AuditKinds kinds;

  this(DirectoryRepositories repos, IDirectoryRepository!(TEntity, TId) repo, IDirectoryEventPublisher publisher,
      AuditTrail audit, NowFn clock, string kindLabel, string topic, AuditKinds kinds) {
    this.repos = repos;
    this.repo = repo;
    this.publisher = publisher;
    this.audit = audit;
    this.clock = clock;
    this.kindLabel = kindLabel;
    this.topic = topic;
    this.kinds = kinds;
  }

  // ── hooks ──────────────────────────────────────────────────────────────

  protected abstract TEntity build(TCreate request);
  protected abstract void apply(ref TEntity entity, TSpec spec);

  /// Throw if the entity must not be removed (in use, predefined, wrong status).
  protected void beforeRemove(TEntity entity) {
  }

  /// Called after the entity was saved (create, update, transitions); `before` is TEntity.init on create.
  protected void afterChange(TEntity entity, TEntity before) {
  }

  /// Called after the entity was removed (cascades).
  protected void afterRemove(TEntity entity) {
  }

  /// Values returned once in the create result (generated secrets).
  protected Json createdData(TEntity entity) {
    return Json.emptyObject;
  }

  // ── queries ────────────────────────────────────────────────────────────

  TEntity get(TenantId tenantId, TId id) {
    return repo.findById(tenantId, id);
  }

  TEntity[] list(TenantId tenantId) {
    auto items = repo.findByTenant(tenantId);
    items.sort!((a, b) => nameOf(a).toLower < nameOf(b).toLower);
    return items;
  }

  // ── commands ───────────────────────────────────────────────────────────

  UsecaseResult create(TCreate request) {
    return guarded(() {
      validate(!request.tenantId.isEmpty, "Tenant ID is required");
      auto entity = build(request);
      entity.createdBy = request.actor;
      entity.updatedBy = request.actor;
      repo.save(entity);
      afterChange(entity, TEntity.init);
      record(entity, kinds.created, request.actor, "created");
      return succeeded(entity.id.value, changeText(kindLabel, nameOf(entity), "created"), createdData(entity));
    });
  }

  UsecaseResult update(TUpdate request) {
    return guarded(() {
      auto entity = require(request.tenantId, request.id);
      auto before = entity;
      apply(entity, request.spec);
      entity.update(request.actor);
      repo.update(entity);
      afterChange(entity, before);
      record(entity, kinds.updated, request.actor, "updated");
      return succeeded(entity.id.value, changeText(kindLabel, nameOf(entity), "updated"));
    });
  }

  UsecaseResult remove(TenantId tenantId, TId id, UserId actor) {
    return guarded(() {
      auto entity = require(tenantId, id);
      beforeRemove(entity);
      repo.remove(entity);
      afterRemove(entity);
      record(entity, kinds.deleted, actor, "deleted");
      return succeeded(entity.id.value, changeText(kindLabel, nameOf(entity), "deleted"));
    });
  }

  // ── helpers ────────────────────────────────────────────────────────────

  /// Apply a state change (activate, lock, revoke, ...).
  protected UsecaseResult transition(TenantId tenantId, TId id, UserId actor, string verb, AuditEventType event,
      scope void delegate(ref TEntity) @safe change) {
    return guarded(() {
      auto entity = require(tenantId, id);
      auto before = entity;
      change(entity);
      entity.update(actor);
      repo.update(entity);
      afterChange(entity, before);
      record(entity, event, actor, verb);
      return succeeded(entity.id.value, changeText(kindLabel, nameOf(entity), verb));
    });
  }

  protected TEntity require(TenantId tenantId, TId id) {
    auto entity = repo.findById(tenantId, id);
    ensureFound(!entity.isNull, kindLabel ~ " '" ~ id.value ~ "' not found");
    return entity;
  }

  /// Display names are unique per tenant: `existing` is the aggregate found by name.
  protected void ensureUnique(const TEntity existing, const TEntity candidate) {
    ensureState(existing.isNull || existing.id == candidate.id,
      kindLabel ~ " '" ~ nameOf(candidate) ~ "' already exists");
  }

  /// Publish the domain event and write the audit entry of a change.
  protected void record(const TEntity entity, AuditEventType event, UserId actor, string verb,
      AuditOutcome outcome = AuditOutcome.success, KeyValue[] details = null) {
    auto payload = Json.emptyObject;
    payload["tenantId"] = entity.tenantId.value;
    payload["id"] = entity.id.value;
    payload["name"] = nameOf(entity);
    payload["actor"] = actor.value;
    publisher.publish(topic ~ "." ~ verb.replace(" ", "-"), payload);
    audit.record(entity.tenantId, event, actor, targetTypeOf(kindLabel), entity.id.value, nameOf(entity),
      changeText(kindLabel, nameOf(entity), verb), outcome, details);
  }
}
