/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Password rules: policy validation, strength classification and expiry.
module neko.directory.domain.services.passwords;

import std.ascii : isUpper, isLower, isDigit, isAlphaNum;
import std.uni : toLower;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Rule violations of `password` (empty if the password is acceptable).
string[] passwordViolations(string password, const PasswordPolicy policy, string userName = "") {
  string[] v;
  if (password.length < policy.minLength)
    v ~= "at least " ~ policy.minLength.to!string ~ " characters";
  if (policy.maxLength > 0 && password.length > policy.maxLength)
    v ~= "at most " ~ policy.maxLength.to!string ~ " characters";
  if (policy.requireUppercase && !password.any!(c => isUpper(c)))
    v ~= "an uppercase letter";
  if (policy.requireLowercase && !password.any!(c => isLower(c)))
    v ~= "a lowercase letter";
  if (policy.requireDigit && !password.any!(c => isDigit(c)))
    v ~= "a digit";
  if (policy.requireSpecialChar && !password.any!(c => !isAlphaNum(c)))
    v ~= "a special character";
  if (policy.minUniqueChars > 0 && uniqueChars(password) < policy.minUniqueChars)
    v ~= "at least " ~ policy.minUniqueChars.to!string ~ " different characters";
  if (policy.maxRepeatedChars > 0 && longestRun(password) > policy.maxRepeatedChars)
    v ~= "no character repeated more than " ~ policy.maxRepeatedChars.to!string ~ " times in a row";
  if (policy.forbidUserName && userName.length >= 3 && password.toLower.canFind(userName.toLower))
    v ~= "not the user name";
  return v;
}

/// Throw a validation exception if the password violates the policy.
void validatePassword(string password, const PasswordPolicy policy, string userName = "") {
  auto v = passwordViolations(password, policy, userName);
  validate(v.length == 0, "Password does not satisfy policy '" ~ policy.name ~ "': it needs " ~ v.join(", "));
}

/// Throw a validation exception if the policy rules contradict each other.
void validatePolicyRules(const PasswordPolicy p) {
  validate(p.minLength >= 1 && p.minLength <= 256, "minLength must be between 1 and 256");
  validate(p.maxLength >= p.minLength && p.maxLength <= 1024, "maxLength must be between minLength and 1024");
  validate(p.minUniqueChars >= 0 && p.minUniqueChars <= p.minLength, "minUniqueChars must be between 0 and minLength");
  validate(p.maxRepeatedChars >= 0, "maxRepeatedChars must not be negative");
  validate(p.historyCount >= 0 && p.historyCount <= 24, "historyCount must be between 0 and 24");
  validate(p.maxFailedAttempts >= 0 && p.maxFailedAttempts <= 100, "maxFailedAttempts must be between 0 and 100");
  validate(p.lockoutMinutes >= 0 && p.lockoutMinutes <= 525_600, "lockoutMinutes must be between 0 and 525600");
  validate(p.expiryDays >= 0 && p.expiryDays <= 3650, "expiryDays must be between 0 and 3650");
  validate(p.warningDays >= 0 && (p.expiryDays == 0 || p.warningDays < p.expiryDays),
    "warningDays must be smaller than expiryDays");
}

/// Strength class derived from the rules.
PasswordStrength classifyStrength(const PasswordPolicy p) {
  int classes = (p.requireUppercase ? 1 : 0) + (p.requireLowercase ? 1 : 0) + (p.requireDigit ? 1 : 0)
    + (p.requireSpecialChar ? 1 : 0);
  if (p.minLength >= 14 && classes >= 4 && p.historyCount >= 10 && p.maxFailedAttempts > 0)
    return PasswordStrength.enterprise;
  if (p.minLength >= 12 && classes >= 3)
    return PasswordStrength.strong;
  if (p.minLength >= 8 && classes >= 2)
    return PasswordStrength.standard;
  return PasswordStrength.basic;
}

/// True if a password set at `changedAt` has expired at `now`.
bool isPasswordExpired(const PasswordPolicy policy, long changedAt, long now) pure nothrow {
  return policy.expiryDays > 0 && changedAt > 0 && now >= changedAt + policy.expiryDays * stdTimeDay;
}

private size_t uniqueChars(string s) pure {
  bool[dchar] seen;
  foreach (dchar c; s)
    seen[c] = true;
  return seen.length;
}

private size_t longestRun(string s) pure {
  size_t best, run;
  dchar last;
  foreach (dchar c; s) {
    run = c == last ? run + 1 : 1;
    last = c;
    best = run > best ? run : best;
  }
  return best;
}

///
unittest {
  PasswordPolicy p;
  p.name = "Standard";
  assert(passwordViolations("Welcome2026", p, "jane").length == 0);
  assert(passwordViolations("short1A", p).length == 1);
  assert(passwordViolations("alllowercase", p).length == 2); // uppercase, digit
  assert(passwordViolations("Aaaaa1bcd", p).length == 1); // 5 x "a"
  assert(passwordViolations("Jane2026xyz", p, "jane").length == 1); // contains user name
  p.requireSpecialChar = true;
  assert(passwordViolations("Welcome2026", p).length == 1);

  assert(classifyStrength(p) == PasswordStrength.standard);
  p.minLength = 14;
  p.historyCount = 12;
  assert(classifyStrength(p) == PasswordStrength.enterprise);
  validatePolicyRules(p);

  assert(isPasswordExpired(p, 1, 1 + 90 * stdTimeDay));
  assert(!isPasswordExpired(p, 1, 2));
  p.expiryDays = 0;
  assert(!isPasswordExpired(p, 1, long.max / 2));
}
