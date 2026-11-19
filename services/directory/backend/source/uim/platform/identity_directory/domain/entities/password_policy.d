/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.domain.entities.password_policy;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Password and sign-in rules. Exactly one policy per tenant is the default;
/// users may reference another policy by name.
struct PasswordPolicy {
  mixin TenantEntity!PasswordPolicyId;

  string name; /// unique per tenant
  string description;
  /// Derived from the rules (see classifyStrength).
  PasswordStrength strength = PasswordStrength.standard;

  int minLength = 8;
  int maxLength = 128;
  bool requireUppercase = true;
  bool requireLowercase = true;
  bool requireDigit = true;
  bool requireSpecialChar;
  int minUniqueChars = 3;
  int maxRepeatedChars = 3; /// 0 = unlimited
  bool forbidUserName = true;
  int historyCount = 5; /// previous passwords that cannot be reused
  int maxFailedAttempts = 5; /// 0 = no lockout
  int lockoutMinutes = 30; /// 0 = until an administrator unlocks the user
  int expiryDays = 90; /// 0 = passwords do not expire
  int warningDays = 14;

  bool isDefault;
  /// Installed by the seed service; cannot be deleted.
  bool predefined;
}
