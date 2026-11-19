/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Tabular projections of resource payloads, shared by the text based
/// presentation adapters (CLI tables and GtkD list views).
module neko.directory.presentation.tabular;

import neko.directory;
import neko.directory.presentation.resources;

mixin(ShowModule!());

@safe:

/// A table: column headers + string cells.
struct Table {
  string[] headers;
  string[][] rows;

  size_t length() const {
    return rows.length;
  }

  /// Render as aligned plain text (columns capped at maxWidth characters).
  string render(size_t maxWidth = 48) const {
    import std.array : appender;
    import std.utf : count;

    auto widths = headers.map!(h => h.count).array;
    foreach (r; rows)
      foreach (i, c; r)
        if (i < widths.length)
          widths[i] = max(widths[i], min(c.count, maxWidth));

    string cell(string s, size_t w) {
      auto n = s.count;
      if (n > w) {
        import std.range : take;
        import std.conv : text;

        return s.take(w - 1).text ~ "…";
      }
      return s ~ ' '.repeat(w - n).array.idup;
    }

    auto buf = appender!string;
    void line(const string[] cells) {
      foreach (i, w; widths)
        buf.put((i ? "  " : "") ~ cell(i < cells.length ? cells[i] : "", w));
      buf.put("\n");
    }

    line(headers);
    line(widths.map!(w => '-'.repeat(w).array.idup).array);
    foreach (r; rows)
      line(r);
    return buf.data;
  }
}

/// Display text of a payload value: lists are comma separated, key/value
/// records as k=v, records by their name, timestamps without "T"/"Z".
string cellText(Json v) {
  switch (v.type) {
  case Json.Type.array:
    string[] parts;
    foreach (item; v.get!(Json[])) {
      if (item.type == Json.Type.object) {
        if ("key" in item)
          parts ~= fieldString(item, "key") ~ "=" ~ fieldString(item, "value");
        else if ("schema" in item && "value" in item) // extension attribute
          parts ~= fieldString(item, "name") ~ "=" ~ fieldString(item, "value");
        else if ("display" in item && "value" in item) // group member
          parts ~= fieldString(item, "display").length ? fieldString(item, "display") : fieldString(item, "value");
        else if (displayOf(item).length > 0)
          parts ~= displayOf(item);
        else if ("value" in item) // e-mail, phone number
          parts ~= fieldString(item, "value") ~ (fieldBool(item, "primary") ? " *" : "");
        else if ("formatted" in item || "locality" in item) // address
          parts ~= fieldString(item, "formatted").length ? fieldString(item, "formatted")
            : [fieldString(item, "streetAddress"), fieldString(item, "locality"), fieldString(item, "country")]
              .filter!(x => x.length > 0).join(" ");
        else
          parts ~= item.toString;
      } else
        parts ~= jsonText(item);
    }
    return parts.join(", ");
  case Json.Type.bool_:
    return v.get!bool ? "yes" : "no";
  case Json.Type.string:
    auto s = v.get!string;
    // ISO timestamps
    if (s.length == 20 && s[4] == '-' && s[10] == 'T' && s[$ - 1] == 'Z')
      return s[0 .. 10] ~ " " ~ s[11 .. 19];
    return s.replace("\n", " ");
  case Json.Type.null_, Json.Type.undefined:
    return "";
  default:
    return jsonText(v);
  }
}

/// The display name of a payload: name, title, display name or message.
string displayOf(Json row) {
  foreach (key; ["name", "displayName", "userName", "title", "message"]) {
    auto v = fieldString(row, key);
    if (v.length > 0)
      return v;
  }
  return "";
}

/// Project payload rows onto the columns of a resource.
Table tableOf(const ResourceColumn[] columns, const Json[] rows) {
  Table t;
  foreach (c; columns)
    t.headers ~= c.header;
  foreach (row; rows) {
    string[] cells;
    foreach (c; columns)
      cells ~= cellText(member(row, c.field));
    t.rows ~= cells;
  }
  return t;
}

/// A two column (field, value) table of one payload.
Table detailTable(Json payload) {
  Table t;
  t.headers = ["Field", "Value"];
  if (payload.type == Json.Type.object)
    foreach (k, v; payload.get!(Json[string]))
      t.rows ~= [k, cellText(v)];
  t.rows.sort!((a, b) => a[0] < b[0]);
  return t;
}

///
unittest {
  mixin(ShowTest!("tableOf"));

  auto row = parseJsonString(`{"userName": "jane", "details": [{"key": "a", "value": "1"}], "groups": ["x", "y"],
    "members": [{"value": "u1", "type": "user", "display": "Jane"}], "emails": [{"value": "j@x.io", "type": "work", "primary": true}],
    "extendedAttributes": [{"schema": "Enterprise", "name": "costCenter", "value": "4711"}],
    "createdAt": "2026-11-10T10:00:00Z", "active": true}`);
  auto t = tableOf([ResourceColumn("User", "userName"), ResourceColumn("Details", "details"),
      ResourceColumn("Groups", "groups"), ResourceColumn("Members", "members"), ResourceColumn("E-Mails", "emails"),
      ResourceColumn("Extensions", "extendedAttributes"), ResourceColumn("Created", "createdAt"),
      ResourceColumn("Active", "active")], [row]);
  assert(t.rows[0] == ["jane", "a=1", "x, y", "Jane", "j@x.io *", "costCenter=4711", "2026-11-10 10:00:00", "yes"], t.rows[0].join("|"));
  assert(t.render.canFind("Extensions"));
  assert(detailTable(row).length == 8);
  assert(displayOf(parseJsonString(`{"userName": "jane"}`)) == "jane");
}
