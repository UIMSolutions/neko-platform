/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Value objects: identifiers, names and service endpoints.
module neko.service.platform.domain.types;

import std.algorithm : all, canFind, startsWith;
import std.ascii : isAlphaNum;
import std.string : strip;
import neko.service.platform.domain.exceptions;

@safe:

/// Strongly typed identifier, so a ServiceId is never passed as a TransferId.
struct Id(string kind) {
  string value;

  bool isEmpty() const pure nothrow {
    return value.length == 0;
  }

  string toString() const pure nothrow {
    return value;
  }
}

alias ServiceId = Id!"service";
alias TransferId = Id!"transfer";

/// Technical service name: 3–63 characters, lower-case letters, digits and '-'.
struct ServiceName {
  string value;

  this(string text) pure {
    auto name = text.strip;
    if (name.length < 3 || name.length > 63)
      throw new ValidationException("Service name must have 3 to 63 characters");
    if (!name.all!(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'))
      throw new ValidationException("Service name may only contain a-z, 0-9 and '-': " ~ name);
    if (name[0] == '-' || name[$ - 1] == '-')
      throw new ValidationException("Service name must not start or end with '-'");
    value = name;
  }
}

/// Where a service can be reached and how its health is checked.
struct ServiceEndpoint {
  string baseUrl;
  string healthPath = "/health";

  this(string baseUrl, string healthPath) pure {
    auto url = baseUrl.strip;
    while (url.length > 0 && url[$ - 1] == '/')
      url = url[0 .. $ - 1];
    if (url.length > 0 && !(url.startsWith("http://") || url.startsWith("https://")))
      throw new ValidationException("Base URL must start with http:// or https://: " ~ baseUrl);
    if (url.canFind(' '))
      throw new ValidationException("Base URL must not contain spaces");

    auto path = healthPath.strip;
    if (path.length == 0)
      path = "/health";
    if (path[0] != '/')
      path = "/" ~ path;

    this.baseUrl = url;
    this.healthPath = path;
  }

  /// A service without URL is catalogued but cannot be probed.
  bool isProbeable() const pure nothrow {
    return baseUrl.length > 0;
  }

  string healthUrl() const pure nothrow {
    return baseUrl ~ healthPath;
  }
}

///
unittest {
  assert(ServiceName("management").value == "management");
  bool failed;
  try
    ServiceName("Bad Name");
  catch (ValidationException)
    failed = true;
  assert(failed);

  auto ep = ServiceEndpoint("http://localhost:8098/", "api/v1/health");
  assert(ep.healthUrl == "http://localhost:8098/api/v1/health");
  assert(!ServiceEndpoint("", "").isProbeable);
}
