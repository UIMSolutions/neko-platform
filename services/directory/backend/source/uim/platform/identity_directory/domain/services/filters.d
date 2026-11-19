/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// SCIM 2.0 filter expressions (RFC 7644 section 3.4.2.2), evaluated against
/// JSON representations. Used for dynamic group rules, SCIM list filters and
/// SCIM PATCH value paths.
///
///   userType eq "employee" and (title co "sales" or emails[type eq "work" and value ew "@example.com"])
///   not (active eq false) · name.familyName sw "D" · externalId pr · meta.lastModified gt "2026-01-01T00:00:00Z"
module neko.directory.domain.services.filters;

import std.ascii : isAlphaNum, isWhite, isDigit;
import std.uni : toLower, icmp;
import neko.directory;

mixin(ShowModule!());

@safe:

/// Node of a parsed filter.
class ScimFilter {
  enum Kind { and_, or_, not_, compare, present, valuePath }

  Kind kind;
  string path; /// attribute path ("name.familyName")
  string op; /// eq ne co sw ew gt ge lt le
  Json value; /// comparison literal
  ScimFilter left, right; /// and / or / not (left only) / valuePath (left = element filter)

  /// True if the filter matches a JSON object.
  bool matches(Json resource) const {
    final switch (kind) {
    case Kind.and_:
      return left.matches(resource) && right.matches(resource);
    case Kind.or_:
      return left.matches(resource) || right.matches(resource);
    case Kind.not_:
      return !left.matches(resource);
    case Kind.present:
      return resolve(resource, path).any!(v => isPresent(v));
    case Kind.compare:
      return resolve(resource, path).any!(v => compare(v, op, value));
    case Kind.valuePath:
      return resolve(resource, path).any!(v => v.type == Json.Type.object && left.matches(v));
    }
  }
}

/// Parse a filter; throws DirectoryValidationException on syntax errors.
ScimFilter parseScimFilter(string text) {
  auto p = FilterParser(text);
  auto f = p.parseOr();
  p.skipBlanks();
  validate(p.pos >= p.text.length, "Invalid filter: unexpected '" ~ p.rest ~ "'");
  return f;
}

/// Values at a path; arrays are flattened, keys match case-insensitively.
Json[] resolve(Json resource, string path) {
  Json[] current = [resource];
  auto segments = path.split(".");
  // "urn:ietf:...:2.0:User:costCenter" — the URN (which may contain dots) is one key
  if (path.startsWith("urn:")) {
    auto colon = path.lastIndexOf(':');
    current = child(resource, path[0 .. colon]);
    segments = path[colon + 1 .. $].split(".");
  }
  foreach (segment; segments) {
    Json[] next;
    foreach (c; current) {
      if (c.type == Json.Type.array) {
        foreach (item; c.get!(Json[]))
          next ~= child(item, segment);
      } else
        next ~= child(c, segment);
    }
    current = next;
  }
  Json[] flat;
  foreach (c; current) {
    if (c.type == Json.Type.array)
      flat ~= c.get!(Json[]);
    else
      flat ~= c;
  }
  return flat;
}

private Json[] child(Json obj, string key) {
  if (obj.type != Json.Type.object)
    return null;
  foreach (k, v; obj.get!(Json[string]))
    if (icmp(k, key) == 0)
      return [v];
  // URN-qualified attribute: "urn:...:User:costCenter" is handled by the caller via a full key
  return null;
}

private bool isPresent(Json v) {
  switch (v.type) {
  case Json.Type.undefined, Json.Type.null_:
    return false;
  case Json.Type.string:
    return v.get!string.length > 0;
  case Json.Type.array:
    return v.length > 0;
  default:
    return true;
  }
}

private bool compare(Json actual, string op, Json expected) {
  if (actual.type == Json.Type.undefined)
    return false;
  if (expected.type == Json.Type.null_)
    return op == "eq" ? actual.type == Json.Type.null_ : op == "ne" ? actual.type != Json.Type.null_ : false;
  if (expected.type == Json.Type.bool_) {
    auto a = jsonBool(actual, !expected.get!bool);
    return op == "eq" ? a == expected.get!bool : op == "ne" ? a != expected.get!bool : false;
  }
  if (expected.type == Json.Type.int_ || expected.type == Json.Type.float_) {
    double a, e = expected.type == Json.Type.int_ ? cast(double) expected.get!long : expected.get!double;
    try
      a = jsonText(actual).to!double;
    catch (Exception)
      return op == "ne";
    switch (op) {
    case "eq": return a == e;
    case "ne": return a != e;
    case "gt": return a > e;
    case "ge": return a >= e;
    case "lt": return a < e;
    case "le": return a <= e;
    default: return false;
    }
  }
  auto a = jsonText(actual).toLower;
  auto e = jsonText(expected).toLower;
  switch (op) {
  case "eq": return a == e;
  case "ne": return a != e;
  case "co": return a.canFind(e);
  case "sw": return a.startsWith(e);
  case "ew": return a.endsWith(e);
  case "gt": return a > e;
  case "ge": return a >= e;
  case "lt": return a < e;
  case "le": return a <= e;
  default: return false;
  }
}

private struct FilterParser {
  string text;
  size_t pos;

  string rest() const {
    return text[pos .. $];
  }

  void skipBlanks() {
    while (pos < text.length && isWhite(text[pos]))
      pos++;
  }

  bool keyword(string word) {
    skipBlanks();
    auto end = pos + word.length;
    if (end <= text.length && icmp(text[pos .. end], word) == 0
        && (end == text.length || !isAlphaNum(text[end]))) {
      pos = end;
      return true;
    }
    return false;
  }

  bool symbol(char c) {
    skipBlanks();
    if (pos < text.length && text[pos] == c) {
      pos++;
      return true;
    }
    return false;
  }

  ScimFilter node(ScimFilter.Kind kind, ScimFilter l, ScimFilter r = null) {
    auto f = new ScimFilter;
    f.kind = kind;
    f.left = l;
    f.right = r;
    return f;
  }

  ScimFilter parseOr() {
    auto l = parseAnd();
    while (keyword("or"))
      l = node(ScimFilter.Kind.or_, l, parseAnd());
    return l;
  }

  ScimFilter parseAnd() {
    auto l = parseUnary();
    while (keyword("and"))
      l = node(ScimFilter.Kind.and_, l, parseUnary());
    return l;
  }

  ScimFilter parseUnary() {
    if (keyword("not")) {
      validate(symbol('('), "Invalid filter: 'not' must be followed by '('");
      auto inner = parseOr();
      validate(symbol(')'), "Invalid filter: missing ')'");
      return node(ScimFilter.Kind.not_, inner);
    }
    if (symbol('(')) {
      auto inner = parseOr();
      validate(symbol(')'), "Invalid filter: missing ')'");
      return inner;
    }
    return parseAttribute();
  }

  ScimFilter parseAttribute() {
    auto path = attributePath();
    validate(path.length > 0, "Invalid filter: attribute expected at '" ~ rest ~ "'");
    if (symbol('[')) {
      auto f = node(ScimFilter.Kind.valuePath, parseOr());
      f.path = path;
      validate(symbol(']'), "Invalid filter: missing ']'");
      return f;
    }
    auto f = new ScimFilter;
    f.path = path;
    if (keyword("pr")) {
      f.kind = ScimFilter.Kind.present;
      return f;
    }
    foreach (op; ["eq", "ne", "co", "sw", "ew", "gt", "ge", "lt", "le"])
      if (keyword(op)) {
        f.kind = ScimFilter.Kind.compare;
        f.op = op;
        f.value = literal();
        return f;
      }
    throw new DirectoryValidationException("Invalid filter: operator expected after '" ~ path ~ "'");
  }

  string attributePath() {
    skipBlanks();
    auto start = pos;
    while (pos < text.length && (isAlphaNum(text[pos]) || "._-:$".canFind(text[pos])))
      pos++;
    return text[start .. pos];
  }

  Json literal() {
    skipBlanks();
    validate(pos < text.length, "Invalid filter: value expected");
    if (text[pos] == '"') {
      pos++;
      string s;
      while (pos < text.length && text[pos] != '"') {
        if (text[pos] == '\\' && pos + 1 < text.length)
          pos++;
        s ~= text[pos++];
      }
      validate(pos < text.length, "Invalid filter: unterminated string");
      pos++;
      return Json(s);
    }
    if (keyword("true"))
      return Json(true);
    if (keyword("false"))
      return Json(false);
    if (keyword("null"))
      return Json(null);
    auto start = pos;
    while (pos < text.length && (isDigit(text[pos]) || text[pos] == '.' || text[pos] == '-'))
      pos++;
    auto number = text[start .. pos];
    validate(number.length > 0, "Invalid filter: value expected at '" ~ rest ~ "'");
    return number.canFind(".") ? Json(number.to!double) : Json(number.to!long);
  }
}

///
unittest {
  auto jane = parseJsonString(`{"userName": "jane", "userType": "employee", "active": true, "title": "Sales Manager",
    "name": {"familyName": "Doe"}, "emails": [{"value": "jane@example.com", "type": "work"}, {"value": "j@home.io", "type": "home"}],
    "failedLoginAttempts": 2}`);

  bool m(string f) {
    return parseScimFilter(f).matches(jane);
  }

  assert(m(`userName eq "JANE"`));
  assert(m(`userType eq "employee" and title co "sales"`));
  assert(m(`name.familyName sw "D"`));
  assert(m(`emails.value ew "@example.com"`));
  assert(m(`emails[type eq "work" and value co "example"]`));
  assert(!m(`emails[type eq "home" and value co "example"]`));
  assert(m(`not (active eq false)`));
  assert(m(`title pr`) && !m(`nickName pr`));
  assert(m(`failedLoginAttempts ge 2`) && !m(`failedLoginAttempts gt 2`));
  assert(m(`userType eq "partner" or (active eq true and userName ne "bob")`));

  bool invalid(string f) {
    try
      parseScimFilter(f);
    catch (DirectoryValidationException)
      return true;
    return false;
  }

  assert(invalid(`userName xx "a"`) && invalid(`(userName eq "a"`) && invalid(`userName eq "a" bogus`));
}
