/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.entities.api_client;

import neko.directory;

mixin(ShowModule!());

@safe:

/// A technical user for service-to-service access (client credentials).
/// Only a hash of the secret is stored; the secret is shown once on creation
/// and on rotation.
struct ApiClient {
  mixin TenantEntity!ApiClientId;

  string name; /// unique per tenant
  string description;
  string clientId; /// generated, unique
  string secretHash; /// never exposed
  string secretHint; /// last characters of the current secret
  string[] scopes;
  ApiClientStatus status = ApiClientStatus.active;
  long expiresAt; /// 0 = no expiry
  long secretRotatedAt;
  long lastUsedAt;
}

/// True if the client has an expiry date that lies before `now`.
bool isExpiredAt(const ApiClient client, long now) pure nothrow {
  return client.expiresAt > 0 && client.expiresAt <= now;
}

///
unittest {
  auto c = ApiClient(TenantId("t1"));
  assert(!c.isExpiredAt(100));
  c.expiresAt = 50;
  assert(c.isExpiredAt(100) && !c.isExpiredAt(49));
}
