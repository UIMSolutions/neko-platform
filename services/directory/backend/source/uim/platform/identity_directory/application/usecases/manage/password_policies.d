/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.application.usecases.manage.password_policies;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Interactor: password policies. The first policy becomes the default;
/// the default, predefined and referenced policies cannot be deleted.
class ManagePasswordPoliciesUseCase
  : ResourceUseCase!(PasswordPolicy, PasswordPolicyId, CreatePasswordPolicyRequest, UpdatePasswordPolicyRequest),
  IManagePasswordPoliciesUseCase {

  this(DirectoryRepositories repos, IDirectoryEventPublisher publisher, AuditTrail audit, NowFn clock) {
    super(repos, repos.policies, publisher, audit, clock, "Password policy", "identity.password-policy",
      AuditKinds(AuditEventType.policyCreated, AuditEventType.policyUpdated, AuditEventType.policyDeleted));
  }

  override protected PasswordPolicy build(CreatePasswordPolicyRequest r) {
    auto policy = PasswordPolicy(r.tenantId);
    assignMatching(policy, r.spec);
    check(policy);
    policy.isDefault = repo.findMatching(r.tenantId, (const PasswordPolicy p) => p.isDefault).length == 0;
    return policy;
  }

  override protected void apply(ref PasswordPolicy policy, PasswordPolicySpec spec) {
    auto before = policy.name;
    assignMatching(policy, spec);
    check(policy);
    if (!sameName(before, policy.name))
      ensureState(usersOf(policy.tenantId, before) == 0, "Password policy '" ~ before ~ "' is referenced by users — it cannot be renamed");
  }

  protected void check(ref PasswordPolicy policy) {
    policy.name = policy.name.strip;
    validateDisplayName("Policy name", policy.name, 80);
    ensureUnique(repo.findByName(policy.tenantId, policy.name), policy);
    validatePolicyRules(policy);
    policy.strength = classifyStrength(policy);
  }

  override protected void beforeRemove(PasswordPolicy policy) {
    ensureState(!policy.predefined, "Password policy '" ~ policy.name ~ "' is predefined and cannot be deleted");
    ensureState(!policy.isDefault || repo.findByTenant(policy.tenantId).length == 1,
      "Password policy '" ~ policy.name ~ "' is the default — make another policy the default first");
    auto n = usersOf(policy.tenantId, policy.name);
    ensureState(n == 0, "Password policy '" ~ policy.name ~ "' is used by " ~ n.to!string ~ " user(s)");
  }

  protected size_t usersOf(TenantId tenantId, string name) {
    return repos.users.findMatching(tenantId, (const DirectoryUser u) => sameName(u.passwordPolicy, name)).length;
  }

  UsecaseResult makeDefault(TenantId tenantId, PasswordPolicyId id, UserId actor) {
    auto result = transition(tenantId, id, actor, "made default", AuditEventType.policyUpdated, (ref PasswordPolicy p) {
      ensureState(!p.isDefault, "Password policy '" ~ p.name ~ "' is already the default");
      p.isDefault = true;
    });
    if (result.isSuccess)
      foreach (other; repo.findMatching(tenantId, (const PasswordPolicy p) => p.isDefault && p.id != id)) {
        other.isDefault = false;
        repo.update(other);
      }
    return result;
  }

  PasswordPolicy policyFor(TenantId tenantId, string policyName) {
    if (policyName.length > 0) {
      auto p = repo.findByName(tenantId, policyName);
      if (!p.isNull)
        return p;
    }
    auto defaults = repo.findMatching(tenantId, (const PasswordPolicy p) => p.isDefault);
    return defaults.length > 0 ? defaults[0] : PasswordPolicy.init;
  }
}
