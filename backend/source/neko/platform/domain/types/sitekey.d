/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.types.sitekey;

import std.algorithm : all;
import std.ascii : isDigit, isLower;
import std.string : strip, toLower;
import neko.platform.domain.exceptions;

@safe:

/// Key of a site (tenant): 2–32 characters a-z, 0-9 and '-', starting with a
/// letter. It names the site's file folder and cannot change.
struct SiteKey {
  string value;

  this(string text) pure {
    auto key = text.strip.toLower;
    if (key.length < 2 || key.length > 32)
      throw new ValidationException("Site key must have 2 to 32 characters");
    if (!key[0].isLower || !key.all!(c => c.isLower || c.isDigit || c == '-'))
      throw new ValidationException("Site key must start with a-z and may only contain a-z, 0-9 and '-'");
    value = key;
  }
}

///
unittest {
  assert(SiteKey(" Shop-DE ").value == "shop-de");
  foreach (bad; ["a", "9shop", "shop_de", "shop de", "../x", "ä-shop", ""]) {
    bool failed;
    try
      SiteKey(bad);
    catch (ValidationException)
      failed = true;
    assert(failed, bad);
  }
}
