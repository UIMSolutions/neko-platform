/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// XSUAA / JWT identity and browser security policies.
module neko.platform.infrastructure.security;

import std.algorithm : any, endsWith, startsWith;
import std.base64 : Base64URLNoPadding;
import std.string : strip, stripRight;
import vibe.data.json;

public import neko.platform.infrastructure.security.passwords;

@safe:

/// Strict policy for the API: nothing may be loaded or framed.
enum apiContentSecurityPolicy = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'";

/// Policy for the UI. Everything is loaded from this origin (important in
/// isolated domains — UI5 must be served locally, see frontend/README).
/// UI5 renders inline style attributes, hence style-src 'unsafe-inline'.
enum uiContentSecurityPolicy = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; "
  ~ "font-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";

struct RequestIdentity {
  string user = "anonymous";
  string[] scopes;
  /// True if user and scopes come from a bearer token.
  bool fromToken;

  /// XSUAA scopes are "<xsappname>.<scope>"; match on the local part.
  bool hasScope(string localName) const {
    return scopes.any!(s => s == localName || s.endsWith("." ~ localName));
  }
}

/// Decode the payload of a JWT.
///
/// SECURITY: the signature is NOT verified. Behind the approuter the token has
/// been validated by XSUAA already; a backend that is reachable directly must
/// verify it (XSUAA verification key / JWKS) before trusting these claims.
Json decodeJwtClaims(string token) {
  import std.array : split;

  auto parts = token.split(".");
  if (parts.length != 3)
    return Json.undefined;
  try {
    auto bytes = Base64URLNoPadding.decode(parts[1].stripRight("="));
    return parseJsonString((() @trusted => cast(string) bytes.idup)());
  } catch (Exception)
    return Json.undefined;
}

/// Identity from an XSUAA bearer token, else from the X-User-Id header.
RequestIdentity resolveIdentity(string authorization, string userHeader) {
  RequestIdentity identity;
  if (authorization.startsWith("Bearer ")) {
    auto claims = decodeJwtClaims(authorization["Bearer ".length .. $].strip);
    if (claims.type == Json.Type.object) {
      identity.fromToken = true;
      foreach (key; ["user_name", "email", "client_id"])
        if (auto v = key in claims)
          if (v.type == Json.Type.string && v.get!string.length > 0) {
            identity.user = v.get!string;
            break;
          }
      if (auto scope_ = "scope" in claims)
        if (scope_.type == Json.Type.array)
          foreach (s; scope_.get!(Json[]))
            if (s.type == Json.Type.string)
              identity.scopes ~= s.get!string;
    }
  }
  if (!identity.fromToken && userHeader.strip.length > 0)
    identity.user = userHeader.strip;
  return identity;
}

///
unittest {
  auto payload = Base64URLNoPadding.encode(cast(const(ubyte)[]) `{"user_name":"jane","scope":["neko!t1.Admin","openid"]}`);
  auto identity = resolveIdentity("Bearer eyJhbGciOiJub25lIn0." ~ payload.idup ~ ".sig", "ignored");
  assert(identity.fromToken && identity.user == "jane");
  assert(identity.hasScope("Admin") && !identity.hasScope("Viewer"));

  auto header = resolveIdentity("", "bob");
  assert(!header.fromToken && header.user == "bob" && !header.hasScope("Admin"));
  assert(resolveIdentity("Bearer garbage", "").user == "anonymous");
}
