/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The subset of OData system query options used by NEKO Fiori lists:
///   $filter   Field eq|ne 'v' | contains(Field,'v') | startswith(Field,'v'), joined by "and"
///   $orderby  Field [asc|desc][, …]
///   $search   free text over all string properties
///   $select   Field,Field
///   $top / $skip / $count=true
/// Data sets here are small (catalogue, audit trail), so options are applied
/// in memory after loading.
module neko.platform.presentation.odata.query;

import std.algorithm : all, any, canFind, map, sort, splitter, startsWith, endsWith;
import std.array : array, split;
import std.conv : to;
import std.string : indexOf, strip, toLower;
import std.uni : asLowerCase;
import vibe.data.json;
import neko.platform.domain.exceptions : ValidationException;

@safe:

struct Condition {
  string op; /// eq, ne, contains, startswith
  string field;
  string value;
}

struct OrderBy {
  string field;
  bool descending;
}

struct QueryOptions {
  Condition[] filter;
  OrderBy[] orderBy;
  string search;
  string[] select;
  long top = -1;
  long skip;
  bool count;
}

private string unquote(string text) {
  auto t = text.strip;
  if (t.length < 2 || t[0] != '\'' || t[$ - 1] != '\'')
    throw new ValidationException("Expected a quoted string literal, got: " ~ text);
  import std.array : replace;

  return t[1 .. $ - 1].replace("''", "'");
}

/// "(a and b)" → "a and b", but "(a) and (b)" stays (the first paren closes early).
private string stripOuterParens(string expr) {
  auto t = expr.strip;
  while (t.length >= 2 && t[0] == '(' && t[$ - 1] == ')') {
    int depth;
    bool quoted, wraps = true;
    foreach (i, c; t) {
      if (c == '\'')
        quoted = !quoted;
      else if (!quoted && c == '(')
        depth++;
      else if (!quoted && c == ')' && --depth == 0 && i + 1 < t.length) {
        wraps = false;
        break;
      }
    }
    if (!wraps)
      break;
    t = t[1 .. $ - 1].strip;
  }
  return t;
}

/// Split on " and " outside of string literals.
private string[] splitAnd(string expr) {
  string[] parts;
  bool quoted;
  size_t start;
  for (size_t i = 0; i < expr.length; i++) {
    if (expr[i] == '\'')
      quoted = !quoted;
    else if (!quoted && i + 5 <= expr.length && expr[i .. i + 5] == " and ") {
      parts ~= expr[start .. i];
      start = i + 5;
      i += 4;
    }
  }
  parts ~= expr[start .. $];
  return parts;
}

Condition parseCondition(string text) {
  auto t = text.strip;
  while (t.startsWith("(") && t.endsWith(")"))
    t = t[1 .. $ - 1].strip;
  foreach (fn; ["contains", "startswith"]) {
    if (t.startsWith(fn ~ "(") && t.endsWith(")")) {
      auto args = t[fn.length + 1 .. $ - 1];
      auto comma = args.indexOf(',');
      if (comma < 0)
        throw new ValidationException("Invalid " ~ fn ~ "() in $filter");
      return Condition(fn, args[0 .. comma].strip, unquote(args[comma + 1 .. $]));
    }
  }
  foreach (op; ["eq", "ne"]) {
    auto pos = t.indexOf(" " ~ op ~ " ");
    if (pos > 0)
      return Condition(op, t[0 .. pos].strip, unquote(t[pos + op.length + 2 .. $]));
  }
  throw new ValidationException("Unsupported $filter expression: " ~ text);
}

QueryOptions parseQuery(string[string] params) {
  QueryOptions q;
  if (auto f = "$filter" in params)
    if ((*f).strip.length > 0)
      foreach (part; splitAnd(stripOuterParens(*f)))
        q.filter ~= parseCondition(part);
  if (auto o = "$orderby" in params)
    foreach (part; (*o).split(",")) {
      auto words = part.strip.split(" ");
      if (words.length == 0 || words[0].length == 0)
        continue;
      q.orderBy ~= OrderBy(words[0], words.length > 1 && words[$ - 1].toLower == "desc");
    }
  if (auto s = "$search" in params) {
    auto text = (*s).strip;
    if (text.length >= 2 && text[0] == '"' && text[$ - 1] == '"')
      text = text[1 .. $ - 1];
    q.search = text.toLower;
  }
  if (auto s = "$select" in params)
    q.select = (*s).split(",").map!(f => f.strip).array;
  try {
    if (auto t = "$top" in params)
      q.top = (*t).to!long;
    if (auto s = "$skip" in params)
      q.skip = (*s).to!long;
  } catch (Exception)
    throw new ValidationException("$top and $skip must be integers");
  if (auto c = "$count" in params)
    q.count = *c == "true";
  return q;
}

private string text(Json entity, string field) {
  auto v = field in entity;
  if (v is null)
    throw new ValidationException("Unknown property '" ~ field ~ "'");
  if (v.type == Json.Type.string)
    return v.get!string;
  if (v.type == Json.Type.null_)
    return "";
  return v.toString;
}

private bool matches(Json entity, const Condition c) {
  auto value = text(entity, c.field);
  final switch (c.op) {
  case "eq":
    return value == c.value;
  case "ne":
    return value != c.value;
  case "contains":
    return value.toLower.canFind(c.value.toLower);
  case "startswith":
    return value.toLower.startsWith(c.value.toLower);
  }
}

private bool matchesSearch(Json entity, string search) {
  foreach (string key, value; entity.byKeyValue)
    if (value.type == Json.Type.string && value.get!string.toLower.canFind(search))
      return true;
  return false;
}

private auto byKeyValue(Json entity) @trusted {
  return entity.get!(Json[string]);
}

/// Filter, search and sort; returns the full matching list (before paging).
Json[] applyFilter(Json[] entities, const QueryOptions q) {
  Json[] result;
  foreach (e; entities) {
    if (!q.filter.all!(c => matches(e, c)))
      continue;
    if (q.search.length > 0 && !matchesSearch(e, q.search))
      continue;
    result ~= e;
  }
  if (q.orderBy.length > 0) {
    foreach (o; q.orderBy)
      if (result.length > 0)
        text(result[0], o.field); // validate property names
    result.sort!((a, b) {
      foreach (o; q.orderBy) {
        auto x = text(a, o.field), y = text(b, o.field);
        if (x != y)
          return o.descending ? x > y : x < y;
      }
      return false;
    });
  }
  return result;
}

Json[] applyPaging(Json[] entities, const QueryOptions q) {
  auto skip = q.skip > 0 ? cast(size_t) q.skip : 0;
  if (skip >= entities.length)
    return [];
  auto rest = entities[skip .. $];
  if (q.top >= 0 && cast(size_t) q.top < rest.length)
    rest = rest[0 .. cast(size_t) q.top];
  return rest;
}

/// Keep only the selected properties (the key is always kept).
Json applySelect(Json entity, const QueryOptions q, string key) {
  if (q.select.length == 0 || q.select.canFind("*"))
    return entity;
  auto j = Json.emptyObject;
  j[key] = entity[key];
  foreach (field; q.select)
    if (auto v = field in entity)
      j[field] = *v;
  return j;
}

///
unittest {
  auto q = parseQuery(["$filter": "Status eq 'active' and contains(Name,'ma')", "$orderby": "Name desc",
    "$top": "1", "$count": "true"]);
  assert(q.filter.length == 2 && q.filter[1].op == "contains" && q.count && q.top == 1);

  Json[] rows = [
    Json(["ID": Json("1"), "Name": Json("management"), "Status": Json("active")]),
    Json(["ID": Json("2"), "Name": Json("mail"), "Status": Json("active")]),
    Json(["ID": Json("3"), "Name": Json("mars"), "Status": Json("retired")]),
  ];
  auto filtered = applyFilter(rows, q);
  assert(filtered.length == 2 && filtered[0]["Name"].get!string == "management");
  assert(applyPaging(filtered, q).length == 1);

  assert(parseCondition("Name eq 'it''s'").value == "it's");
  // UI5 wraps combined filters in parentheses
  auto wrapped = parseQuery(["$filter": "(contains(Name,'ma') and Status eq 'active')"]);
  assert(wrapped.filter.length == 2 && applyFilter(rows, wrapped).length == 2);
  assert(parseQuery(["$filter": "(Status eq 'active') and (Name eq 'mail')"]).filter.length == 2);
  auto s = parseQuery(["$search": "\"MAR\""]);
  assert(applyFilter(rows, s).length == 1);
}
