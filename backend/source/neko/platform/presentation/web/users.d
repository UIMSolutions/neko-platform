/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// User management (web interface; dialogs and the table are htmx fragments,
/// see presentation/web/support.d).
///
///   GET  /users                    page                     users.read
///   GET  /users/new                create dialog            users.manage
///   POST /users                    create                   users.manage
///   GET  /users/:id/edit           edit dialog              users.manage
///   POST /users/:id                update                   users.manage
///   GET  /users/:id/password       reset-password dialog    users.manage
///   POST /users/:id/password       reset password           users.manage
///   POST /users/:id/delete         remove                   users.manage
///
/// The use case additionally refuses roles (and accounts) with rights the
/// signed-in user does not hold.
module neko.platform.presentation.web.users;

import std.typecons : nullable;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : CreateUserRequest, RoleDto, SiteDto, UpdateUserRequest, UserDto;
import neko.platform.domain : PlatformException;
import neko.platform.ports.usecases : IManageRolesUseCase, IManageSitesUseCase, IManageUsersUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.support;

@safe:

/// Values of the create / edit dialog.
struct UserForm {
  /// "" = create
  string id;
  string userName;
  string displayName;
  string email;
  string[] roles = ["viewer"];
  /// Site keys; empty = every site.
  string[] sites;
  bool active = true;
  /// Editing the own account: roles and status are locked (no self-lockout).
  bool self;
  string error;

  bool isNew() const {
    return id.length == 0;
  }

  bool hasRole(string name) const {
    import std.algorithm : canFind;

    return roles.canFind(name);
  }

  bool hasSite(string key) const {
    import std.algorithm : canFind;

    return sites.canFind(key);
  }
}

@requiresAuth
class UsersWeb {
  private WebGuard guard;
  private IManageUsersUseCase users;
  private IManageRolesUseCase roles;
  private IManageSitesUseCase sites;

  mixin PageAuthentication;

  this(WebGuard guard, IManageUsersUseCase users, IManageRolesUseCase roles, IManageSitesUseCase sites) {
    this.guard = guard;
    this.users = users;
    this.roles = roles;
    this.sites = sites;
  }

  @auth(Role.usersRead) @path("/users")
  void getUsers(PageContext page) {
    page = page.at("Users", "users");
    auto list = users.list();
    auto roleList = roles.list();
    render!("users.dt", page, list, roleList);
  }

  @auth(Role.usersManage) @path("/users/new")
  void getNew(PageContext page) {
    UserForm form;
    dialog(page, form);
  }

  @auth(Role.usersManage) @path("/users")
  void postUsers(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = readForm(req);
    CreateUserRequest r;
    r.userName = form.userName;
    r.displayName = form.displayName;
    r.email = form.email;
    r.roles = form.roles;
    r.sites = form.sites;
    r.active = form.active;
    r.password = req.form.get("password", "");
    if (form.error.length)
      return dialog(page, form);
    if (r.password != req.form.get("confirm", "")) {
      form.error = "The passwords do not match";
      return dialog(page, form);
    }
    try {
      auto created = users.create(r, page.user.userName);
      table(res, page, "User " ~ created.userName ~ " created", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      dialog(page, form);
    }
  }

  @auth(Role.usersManage) @path("/users/:id/edit")
  void getEdit(PageContext page, HTTPServerResponse res, string _id) {
    UserDto user;
    if (!load(res, page, _id, user))
      return;
    auto form = UserForm(user.id, user.userName, user.displayName, user.email, user.roles.dup, user.sites.dup,
      user.active, user.id == page.user.id);
    dialog(page, form);
  }

  @auth(Role.usersManage) @path("/users/:id")
  void postUser(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    UserDto user;
    if (!load(res, page, _id, user))
      return;
    auto form = readForm(req);
    form.id = user.id;
    form.userName = user.userName;
    form.self = user.id == page.user.id;
    UpdateUserRequest r;
    r.displayName = nullable(form.displayName);
    r.email = nullable(form.email);
    if (form.self) {
      form.roles = user.roles.dup; // shown again on errors
      form.sites = user.sites.dup;
    } else {
      r.roles = nullable(form.roles);
      r.sites = nullable(form.sites);
      r.active = nullable(form.active);
      if (form.error.length)
        return dialog(page, form);
    }
    try {
      auto changed = users.update(user.id, r, page.user.userName);
      if (!changed.active)
        guard.endAllSessions(changed.id);
      table(res, page, "User " ~ changed.userName ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      dialog(page, form);
    }
  }

  @auth(Role.usersManage) @path("/users/:id/password")
  void getPassword(PageContext page, HTTPServerResponse res, string _id) {
    UserDto user;
    if (!load(res, page, _id, user))
      return;
    string error;
    render!("password_dialog.dt", page, user, error);
  }

  @auth(Role.usersManage) @path("/users/:id/password")
  void postPassword(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    UserDto user;
    if (!load(res, page, _id, user))
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
    render!("password_dialog.dt", page, user, error);
  }

  @auth(Role.usersManage) @path("/users/:id/delete")
  void postDelete(PageContext page, HTTPServerResponse res, string _id) {
    UserDto user;
    if (!load(res, page, _id, user))
      return;
    try {
      users.remove(user.id, page.user.userName);
      guard.endAllSessions(user.id);
      table(res, page, "User " ~ user.userName ~ " removed", false);
    } catch (PlatformException e)
      table(res, page, e.msg, true);
  }

  @noRoute void dialog(PageContext page, UserForm form) {
    auto roleList = roles.list();
    auto siteList = sites.list(page.user.userName);
    render!("user_dialog.dt", page, form, roleList, siteList);
  }

  /// Answer with the refreshed table, a toast and "close dialog".
  @noRoute void table(HTTPServerResponse res, PageContext page, string message, bool error) {
    swapTable(res, "users-table", message, error);
    auto list = users.list();
    auto roleList = roles.list();
    render!("users_table.dt", page, list, roleList);
  }

  @noRoute bool load(HTTPServerResponse res, PageContext page, string id, out UserDto user) {
    try {
      user = users.get(id);
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
  form.roles = req.form.getAll("roles").dup;
  // "all" (radio) = every site; otherwise the checked sites
  form.sites = req.form.get("scope", "all") == "all" ? null : req.form.getAll("sites").dup;
  if (req.form.get("scope", "all") != "all" && form.sites.length == 0)
    form.error = "Choose at least one site, or give access to every site";
  form.active = req.form.get("active", "") == "on";
  return form;
}
