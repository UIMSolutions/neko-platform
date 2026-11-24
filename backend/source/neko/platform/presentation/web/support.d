/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// htmx conventions of the management pages.
///
/// Dialogs are Tabler modals loaded into #dialog-host. Their form posts with
/// hx-target="closest .modal-content" and hx-select=".modal-content", so a
/// validation error re-renders the dialog in place. A successful change
/// answers with the refreshed table instead: `swapTable` retargets the
/// response, and the HX-Trigger events nekoNotify (toast) and nekoClose
/// (close the dialog) are handled by app.js.
module neko.platform.presentation.web.support;

import std.algorithm : canFind;
import vibe.data.json : Json;
import vibe.http.server : HTTPServerResponse;
import neko.platform.application.dtos : RoleDto, UserDto;

@safe:

/// Make the response replace `#<id>` and show `message` as a toast.
void swapTable(HTTPServerResponse res, string id, string message, bool error) {
  auto trigger = Json.emptyObject;
  trigger["nekoNotify"] = Json(["message": Json(message), "error": Json(error)]);
  trigger["nekoClose"] = true;
  res.headers["HX-Trigger"] = jsonAscii(trigger.toString);
  res.headers["HX-Retarget"] = "#" ~ id;
  res.headers["HX-Reswap"] = "outerHTML";
  res.headers["HX-Reselect"] = "#" ~ id;
}

/// True if `user` holds every right of `role`, i.e. may hand it out.
bool mayAssign(const UserDto user, const RoleDto role) pure nothrow {
  foreach (r; role.rights)
    if (!user.rights.canFind(r))
      return false;
  return true;
}

/// Serialized JSON with every non-ASCII character as a \\u escape, so it can
/// travel in an HTTP header and still decodes to the original text.
string jsonAscii(string json) pure {
  import std.format : format;
  import std.utf : byDchar;

  string result;
  foreach (dchar c; json.byDchar) {
    if (c < 0x80)
      result ~= cast(char) c;
    else if (c < 0x10000)
      result ~= format("\\u%04x", cast(uint) c);
    else {
      auto v = cast(uint) c - 0x10000;
      result ~= format("\\u%04x\\u%04x", 0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
    }
  }
  return result;
}

/// HTTP header values must stay ASCII.
string asciiOnly(string text) pure {
  auto result = new char[text.length];
  size_t n;
  foreach (char c; text)
    if (c < 0x80)
      result[n++] = c;
    else if ((c & 0xC0) != 0x80) // first byte of a multi-byte sequence
      result[n++] = '?';
  return result[0 .. n].idup;
}

/// "2026-11-19T08:00:00.000Z" → "2026-11-19 08:00"; `none` for unset.
string shortTime(string iso, string none = "–") pure {
  return iso.length >= 16 ? iso[0 .. 10] ~ " " ~ iso[11 .. 16] : none;
}

/// First letter of `text`, upper case, for avatars ("?" if empty).
string initial(string text) pure {
  import std.string : toUpper;
  import std.utf : stride;

  return text.length ? text[0 .. stride(text, 0)].toUpper : "?";
}

///
unittest {
  assert(initial("jane") == "J" && initial("Ömer") == "Ö" && initial("") == "?");
  assert(asciiOnly("User ä removed") == "User ? removed");
  assert(jsonAscii(`{"m":"Grüße 😀"}`) == `{"m":"Gr\u00fc\u00dfe \ud83d\ude00"}`);
  assert(shortTime("2026-11-19T08:00:00.000Z") == "2026-11-19 08:00" && shortTime("", "never") == "never");
  UserDto u;
  u.rights = ["status.read", "users.read"];
  RoleDto r;
  r.rights = ["status.read"];
  assert(mayAssign(u, r));
  r.rights ~= "roles.manage";
  assert(!mayAssign(u, r));
}
