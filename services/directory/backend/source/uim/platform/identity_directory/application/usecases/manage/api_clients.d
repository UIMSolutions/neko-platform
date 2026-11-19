/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.manage.api_clients;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Interactor: API clients. Secrets are generated, shown once and stored as hashes.
class ManageApiClientsUseCase
  : ResourceUseCase!(ApiClient, ApiClientId, CreateApiClientRequest, UpdateApiClientRequest),
  IManageApiClientsUseCase {

  protected ICredentialService credentials;
  /// Secret issued by the last build() — returned once by createdData() (same call, no fiber switch in between).
  private string issued;

  this(DirectoryRepositories repos, ICredentialService credentials, IDirectoryEventPublisher publisher,
      AuditTrail audit, NowFn clock) {
    super(repos, repos.apiClients, publisher, audit, clock, "API client", "identity.api-client",
      AuditKinds(AuditEventType.apiClientCreated, AuditEventType.apiClientUpdated, AuditEventType.apiClientDeleted));
    this.credentials = credentials;
  }

  override protected ApiClient build(CreateApiClientRequest r) {
    auto client = ApiClient(r.tenantId);
    assignMatching(client, r.spec);
    check(client);
    validate(client.expiresAt == 0 || client.expiresAt > clock(), "expiresAt must lie in the future");
    client.clientId = "sb-" ~ credentials.generateSecret(12);
    issued = issueSecret(client);
    return client;
  }

  override protected Json createdData(ApiClient client) {
    auto data = secretData(client, issued);
    issued = null;
    return data;
  }

  override protected void apply(ref ApiClient client, ApiClientSpec spec) {
    assignMatching(client, spec);
    check(client);
  }

  protected void check(ref ApiClient client) {
    client.name = client.name.strip;
    validateDisplayName("API client name", client.name, 80);
    ensureUnique(repo.findByName(client.tenantId, client.name), client);
    client.scopes = normalizedNames(client.scopes);
    foreach (s; client.scopes)
      validate(isScope(s), "Scope '" ~ s ~ "' must not contain blanks or quotes");
  }

  /// Generate a new secret, store its hash and return it.
  protected string issueSecret(ref ApiClient client) {
    auto secret = credentials.generateSecret(32);
    client.secretHash = credentials.hashSecret(secret);
    client.secretHint = "…" ~ secret[$ - 4 .. $];
    client.secretRotatedAt = clock();
    return secret;
  }

  protected static Json secretData(const ApiClient client, string secret) {
    return Json.emptyObject.set("clientId", client.clientId).set("clientSecret", secret);
  }

  UsecaseResult rotateSecret(TenantId tenantId, ApiClientId id, UserId actor) {
    string secret;
    auto result = transition(tenantId, id, actor, "secret rotated", AuditEventType.apiClientSecretRotated, (ref ApiClient c) {
      ensureState(c.status == ApiClientStatus.active, "API client '" ~ c.name ~ "' is " ~ enumText(c.status));
      secret = issueSecret(c);
    });
    if (result.isSuccess)
      result.data = secretData(repo.findById(tenantId, id), secret);
    return result;
  }

  UsecaseResult revoke(TenantId tenantId, ApiClientId id, UserId actor) {
    return transition(tenantId, id, actor, "revoked", AuditEventType.apiClientRevoked, (ref ApiClient c) {
      ensureState(c.status != ApiClientStatus.revoked, "API client '" ~ c.name ~ "' is already revoked");
      c.status = ApiClientStatus.revoked;
    });
  }

  UsecaseResult reactivate(TenantId tenantId, ApiClientId id, UserId actor) {
    return transition(tenantId, id, actor, "reactivated", AuditEventType.apiClientReactivated, (ref ApiClient c) {
      ensureState(c.status != ApiClientStatus.active, "API client '" ~ c.name ~ "' is already active");
      ensureState(!c.isExpiredAt(clock()), "API client '" ~ c.name ~ "' has expired — set a later expiresAt first");
      c.status = ApiClientStatus.active;
    });
  }

  UsecaseResult verify(TenantId tenantId, ApiClientId id, string secret, UserId actor) {
    auto client = repo.findById(tenantId, id);
    if (client.isNull)
      return UsecaseResult(false, "", "API client '" ~ id.value ~ "' not found", 404);
    auto now = clock();
    string failure;
    if (client.status != ApiClientStatus.active)
      failure = "API client '" ~ client.name ~ "' is " ~ enumText(client.status);
    else if (client.isExpiredAt(now))
      failure = "API client '" ~ client.name ~ "' has expired";
    else if (!credentials.verifySecret(secret, client.secretHash))
      failure = "Invalid client credentials";
    if (failure.length > 0) {
      record(client, AuditEventType.loginFailure, actor, "client authentication failed", AuditOutcome.failure);
      return UsecaseResult(false, "", failure, 401);
    }
    client.lastUsedAt = now;
    repo.update(client);
    record(client, AuditEventType.loginSuccess, actor, "client authenticated");
    return succeeded(client.id.value, "API client '" ~ client.name ~ "' authenticated",
      Json.emptyObject.set("clientId", client.clientId).set("scopes", serializeToJson(client.scopes)));
  }
}
