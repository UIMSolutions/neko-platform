/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Tabler icons as inline SVG, compiled into the binary from
/// backend/assets/vendor/icons — no icon font, nothing to fetch.
///
/// In templates: `| !{icon("users")}`. Add an icon by copying its outline SVG
/// (see backend/assets/vendor/README.md) and listing its name below.
module neko.platform.presentation.web.icons;

@safe:

private enum string[] names = [
  "activity-heartbeat", "alert-circle", "alert-triangle", "apps", "arrows-exchange", "ban", "chart-line", "check",
  "circle-check", "clock", "cloud-upload", "code", "database", "download", "external-link", "eye", "eye-off", "file",
  "file-text", "file-zip", "files", "folder", "hexagons", "home", "info-circle", "key", "language",
  "layout-dashboard", "list-details", "lock", "login", "logout", "moon", "movie", "music", "pencil", "photo",
  "player-play", "plus", "refresh", "server", "settings", "shield-check", "shield-lock", "star", "sun", "trash",
  "upload", "user", "user-circle", "user-plus", "users", "world", "x",
];

/// The SVG markup of the named icon; "" for unknown names.
string icon(string name) pure nothrow @nogc {
  switch (name) {
    static foreach (n; names) {
  case n:
      return import("vendor/icons/" ~ n ~ ".svg");
    }
  default:
    return "";
  }
}

///
unittest {
  import std.algorithm : startsWith;

  static foreach (n; names)
    assert(icon(n).startsWith("<svg") && icon(n).length < 2048, n);
  assert(icon("nope") == "");
}
