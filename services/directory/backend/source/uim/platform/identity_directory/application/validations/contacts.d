/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Application-wide input validators: contact data of users.
module neko.directory.application.validations.contacts;

import neko.directory;

mixin(ShowModule!());

@safe:

private enum string[] emailTypes = ["work", "home", "other"];
private enum string[] phoneTypes = ["work", "mobile", "home", "fax", "pager", "other"];

/// Trim and check e-mail addresses; exactly one becomes primary (the first if none is marked).
Email[] normalizeEmails(const Email[] emails) {
  Email[] result;
  foreach (e; emails) {
    auto v = Email(e.value.strip, e.type.strip.length ? e.type.strip.toLower : "work", e.primary);
    if (v.value.length == 0)
      continue;
    validate(isEmail(v.value), "E-mail '" ~ v.value ~ "' is not valid");
    validate(emailTypes.canFind(v.type), "E-mail type '" ~ v.type ~ "' must be one of " ~ emailTypes.join(", "));
    validate(!result.any!(r => sameName(r.value, v.value)), "E-mail '" ~ v.value ~ "' is listed twice");
    result ~= v;
  }
  validate(result.count!(e => e.primary) <= 1, "Only one e-mail can be primary");
  if (result.length > 0 && !result.any!(e => e.primary))
    result[0].primary = true;
  return result;
}

/// Trim and check phone numbers (digits, blanks, + - ( ) / .).
PhoneNumber[] normalizePhoneNumbers(const PhoneNumber[] numbers) {
  PhoneNumber[] result;
  foreach (p; numbers) {
    auto v = PhoneNumber(p.value.strip, p.type.strip.length ? p.type.strip.toLower : "work", p.primary);
    if (v.value.length == 0)
      continue;
    validate(v.value.all!(c => (c >= '0' && c <= '9') || " +-()/.".canFind(c)) && v.value.any!(c => c >= '0' && c <= '9'),
      "Phone number '" ~ v.value ~ "' is not valid");
    validate(phoneTypes.canFind(v.type), "Phone type '" ~ v.type ~ "' must be one of " ~ phoneTypes.join(", "));
    result ~= v;
  }
  validate(result.count!(e => e.primary) <= 1, "Only one phone number can be primary");
  return result;
}

/// Drop empty addresses; derive "formatted" if missing.
PostalAddress[] normalizeAddresses(const PostalAddress[] addresses) {
  PostalAddress[] result;
  foreach (a; addresses) {
    PostalAddress v = a;
    if ([v.formatted, v.streetAddress, v.locality, v.region, v.postalCode, v.country].all!(s => s.strip.length == 0))
      continue;
    if (v.formatted.strip.length == 0)
      v.formatted = [v.streetAddress, (v.postalCode ~ " " ~ v.locality).strip, v.region, v.country]
        .filter!(s => s.strip.length > 0).join(", ");
    validate(v.country.length == 0 || v.country.length == 2, "Country '" ~ v.country ~ "' must be an ISO 3166 alpha-2 code");
    result ~= v;
  }
  return result;
}

///
unittest {
  auto e = normalizeEmails([Email(" a@x.io ", ""), Email("b@x.io", "HOME")]);
  assert(e[0].value == "a@x.io" && e[0].type == "work" && e[0].primary && e[1].type == "home" && !e[1].primary);
  bool fails(scope void delegate() @safe f) {
    try
      f();
    catch (DirectoryValidationException)
      return true;
    return false;
  }

  assert(fails(() { normalizeEmails([Email("a@x.io", "work", true), Email("b@x.io", "work", true)]); }));
  assert(fails(() { normalizeEmails([Email("nope")]); }));
  assert(normalizePhoneNumbers([PhoneNumber("+49 (0)30 1234-5")]).length == 1);
  assert(fails(() { normalizePhoneNumbers([PhoneNumber("call me")]); }));
  auto a = normalizeAddresses([PostalAddress("", "Main St 1", "Berlin", "", "10115", "DE"), PostalAddress()]);
  assert(a.length == 1 && a[0].formatted == "Main St 1, 10115 Berlin, DE");
}
