/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// User management for administrators (htmx: dialogs and the table are
/// fragments swapped into the page).
///
///   GET  /users                    page
///   GET  /users/new                create dialog
///   POST /users                    create
///   GET  /users/:id/edit           edit dialog
///   POST /users/:id                update
///   GET  /users/:id/password       reset-password dialog
///   POST /users/:id/password       reset password
///   POST /users/:id/delete         remove
///
/// Success answers carry the refreshed table (HX-Retarget #users-table) and
/// an HX-Trigger with nekoNotify (snackbar) and nekoClose (close the dialog).
/// Validation errors re-render the dialog with the message.
module neko.platform.presentation.web.users;

import std.typecons : nullable;
import vibe.data.json : Json;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse, render;
import neko.platform.application.dtos : CreateUserRequest, UpdateUserRequest, UserDto;
import neko.platform.domain : PlatformException;
import neko.platform.ports.usecases : IManageUsersUseCase;
import neko.platform.presentation.web.guard;

@safe:

/// Values of the create / edit dialog.
struct UserForm {
  /// "" = create
  string id;
  string userName;
  string displayName;
  string email;
  string role = "viewer";
  bool active = true;
  /// Editing the own account: role and status are locked (no self-lockout).
  bool self;
  string error;

  bool isNew() const {
    return id.length == 0;
  }
}

class UsersController {
  private WebGuard guard;
  private IManageUsersUseCase users;

  this(WebGuard guard, IManageUsersUseCase users) {
    this.guard = guard;
    this.users = users;
  }

  void registerRoutes(URLRouter router) {
    router.get("/users", &index);
    router.get("/users/new", &newDialog);
    router.post("/users", &create);
    router.get("/users/:id/edit", &editDialog);
    router.post("/users/:id", &update);
    router.get("/users/:id/password", &passwordDialog);
    router.post("/users/:id/password", &resetPassword);
    router.post("/users/:id/delete", &remove);
  }

  void index(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "Users", "users", true, page))
      return;
    auto list = users.list();
    res.render!("users.dt", page, list);
  }

  void newDialog(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "Users", "users", true, page))
      return;
    UserForm form;
    res.render!("user_dialog.dt", page, form);
  }

  void create(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.requirePost(req, res, "Users", "users", true, page))
      return;
    auto form = readForm(req);
    CreateUserRequest r;
    r.userName = form.userName;
    r.displayName = form.displayName;
    r.email = form.email;
    r.role = form.role;
    r.active = form.active;
    r.password = req.form.get("password", "");
    if (r.password != req.form.get("confirm", "")) {
      form.error = "The passwords do not match";
      res.render!("user_dialog.dt", page, form);
      return;
    }
    try {
      auto created = users.create(r, page.user.userName);
      table(res, page, "User " ~ created.userName ~ " created", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      res.render!("user_dialog.dt", page, form);
    }
  }

  void editDialog(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "Users", "users", true, page))
      return;
    UserDto user;
    if (!load(req, res, page, user))
      return;
    auto form = UserForm(user.id, user.userName, user.displayName, user.email, user.role, user.active,
      user.id == page.user.id);
    res.render!("user_dialog.dt", page, form);
  }

  void update(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.requirePost(req, res, "Users", "users", true, page))
      return;
    UserDto user;
    if (!load(req, res, page, user))
      return;
    auto form = readForm(req);
    form.id = user.id;
    form.userName = user.userName;
    form.self = user.id == page.user.id;
    UpdateUserRequest r;
    r.displayName = nullable(form.displayName);
    r.email = nullable(form.email);
    if (!form.self) {
      r.role = nullable(form.role);
      r.active = nullable(form.active);
    }
    try {
      auto changed = users.update(user.id, r, page.user.userName);
      if (!changed.active)
        guard.endAllSessions(changed.id);
      table(res, page, "User " ~ changed.userName ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      res.render!("user_dialog.dt", page, form);
    }
  }

  void passwordDialog(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.require(req, res, "Users", "users", true, page))
      return;
    UserDto user;
    if (!load(req, res, page, user))
      return;
    string error;
    res.render!("password_dialog.dt", page, user, error);
  }

  void resetPassword(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.requirePost(req, res, "Users", "users", true, page))
      return;
    UserDto user;
    if (!load(req, res, page, user))
      return;
    string error;
    auto password = req.form.get("password", "");
    if (password != req.form.get("confirm", ""))
      error = "The passwords do not match";
    else
      try {
        users.resetPassword(user.id, password, page.user.userName);
        if (user.id != page.user.id)
          guard.endAllSessions(user.id);
        table(res, page, "Password of " ~ user.userName ~ " reset", false);
        return;
      } catch (PlatformException e)
        error = e.msg;
    res.render!("password_dialog.dt", page, user, error);
  }

  void remove(HTTPServerRequest req, HTTPServerResponse res) {
    PageContext page;
    if (!guard.requirePost(req, res, "Users", "users", true, page))
      return;
    UserDto user;
    if (!load(req, res, page, user))
      return;
    try {
      users.remove(user.id, page.user.userName);
      guard.endAllSessions(user.id);
      table(res, page, "User " ~ user.userName ~ " removed", false);
    } catch (PlatformException e)
      table(res, page, e.msg, true);
  }

  /// Answer with the refreshed table, a snackbar message and "close dialog".
  private void table(HTTPServerResponse res, PageContext page, string message, bool error) {
    auto trigger = Json.emptyObject;
    trigger["nekoNotify"] = Json(["message": Json(asciiOnly(message)), "error": Json(error)]);
    trigger["nekoClose"] = true;
    res.headers["HX-Trigger"] = trigger.toString;
    res.headers["HX-Retarget"] = "#users-table";
    res.headers["HX-Reswap"] = "outerHTML";
    auto list = users.list();
    res.render!("users_table.dt", page, list);
  }

  private bool load(HTTPServerRequest req, HTTPServerResponse res, PageContext page, out UserDto user) {
    try {
      user = users.get(req.params["id"]);
      return true;
    } catch (PlatformException e) {
      table(res, page, e.msg, true); // e.g. removed in another tab meanwhile
      return false;
    }
  }
}

private UserForm readForm(HTTPServerRequest req) {
  UserForm form;
  form.userName = req.form.get("userName", "");
  form.displayName = req.form.get("displayName", "");
  form.email = req.form.get("email", "");
  form.role = req.form.get("role", "viewer");
  form.active = req.form.get("active", "") == "on";
  return form;
}

/// HTTP header values must stay ASCII.
private string asciiOnly(string text) pure {
  auto result = new char[text.length];
  size_t n;
  foreach (char c; text)
    if (c < 0x80)
      result[n++] = c;
    else if ((c & 0xC0) != 0x80) // first byte of a multi-byte sequence
      result[n++] = '?';
  return result[0 .. n].idup;
}

///
unittest {
  assert(asciiOnly("User ä removed") == "User ? removed");
}
