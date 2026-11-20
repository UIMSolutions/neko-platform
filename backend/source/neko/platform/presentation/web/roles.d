/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Roles and access rights (web interface; htmx fragments as for users).
///
///   GET  /roles                 page: roles and the rights matrix   roles.read
///   GET  /roles/new             create dialog                       roles.manage
///   POST /roles                 create                              roles.manage
///   GET  /roles/:name/edit      edit dialog                         roles.manage
///   POST /roles/:name           update                              roles.manage
///   POST /roles/:name/delete    remove                              roles.manage
///
/// The use case refuses rights the signed-in user does not hold itself.
module neko.platform.presentation.web.roles;

import std.typecons : nullable;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : AccessRightDto, CreateRoleRequest, RoleDto, UpdateRoleRequest;
import neko.platform.domain : PlatformException;
import neko.platform.ports.usecases : IManageRolesUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.support;

@safe:

/// Values of the create / edit dialog.
struct RoleForm {
  /// false = create
  bool existing;
  string name;
  string label;
  string description;
  string[] rights;
  /// The administrator role: rights fixed.
  bool locked;
  bool builtIn;
  string error;

  bool grants(string key) const {
    import std.algorithm : canFind;

    return rights.canFind(key);
  }
}

@requiresAuth
class RolesWeb {
  private WebGuard guard;
  private IManageRolesUseCase roles;

  mixin PageAuthentication;

  this(WebGuard guard, IManageRolesUseCase roles) {
    this.guard = guard;
    this.roles = roles;
  }

  @auth(Role.rolesRead) @path("/roles")
  void getRoles(PageContext page) {
    page = page.at("Roles & rights", "roles");
    auto list = roles.list();
    auto catalogue = roles.rights();
    render!("roles.dt", page, list, catalogue);
  }

  @auth(Role.rolesManage) @path("/roles/new")
  void getNew(PageContext page) {
    RoleForm form;
    dialog(page, form);
  }

  @auth(Role.rolesManage) @path("/roles")
  void postRoles(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = readForm(req);
    try {
      auto created = roles.create(CreateRoleRequest(form.name, form.label, form.description, form.rights),
        page.user.userName);
      table(res, page, "Role " ~ created.name ~ " created", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      dialog(page, form);
    }
  }

  @auth(Role.rolesManage) @path("/roles/:name/edit")
  void getEdit(PageContext page, HTTPServerResponse res, string _name) {
    RoleDto role;
    if (!load(res, page, _name, role))
      return;
    auto form = RoleForm(true, role.name, role.label, role.description, role.rights.dup, role.locked, role.builtIn);
    dialog(page, form);
  }

  @auth(Role.rolesManage) @path("/roles/:name")
  void postRole(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _name) {
    RoleDto role;
    if (!load(res, page, _name, role))
      return;
    auto form = readForm(req);
    form.existing = true;
    form.name = role.name;
    form.locked = role.locked;
    form.builtIn = role.builtIn;
    UpdateRoleRequest r;
    r.label = nullable(form.label);
    r.description = nullable(form.description);
    if (role.locked)
      form.rights = role.rights.dup;
    else
      r.rights = nullable(form.rights);
    try {
      auto changed = roles.update(role.name, r, page.user.userName);
      table(res, page, "Role " ~ changed.name ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      dialog(page, form);
    }
  }

  @auth(Role.rolesManage) @path("/roles/:name/delete")
  void postDelete(PageContext page, HTTPServerResponse res, string _name) {
    try {
      roles.remove(_name, page.user.userName);
      table(res, page, "Role " ~ _name ~ " removed", false);
    } catch (PlatformException e)
      table(res, page, e.msg, true);
  }

  @noRoute void dialog(PageContext page, RoleForm form) {
    auto catalogue = roles.rights();
    render!("role_dialog.dt", page, form, catalogue);
  }

  /// Answer with the refreshed roles card (table and matrix), a toast and "close dialog".
  @noRoute void table(HTTPServerResponse res, PageContext page, string message, bool error) {
    swapTable(res, "roles-table", message, error);
    auto list = roles.list();
    auto catalogue = roles.rights();
    render!("roles_table.dt", page, list, catalogue);
  }

  @noRoute bool load(HTTPServerResponse res, PageContext page, string name, out RoleDto role) {
    try {
      role = roles.get(name);
      return true;
    } catch (PlatformException e) {
      table(res, page, e.msg, true);
      return false;
    }
  }
}

private RoleForm readForm(HTTPServerRequest req) {
  RoleForm form;
  form.name = req.form.get("name", "");
  form.label = req.form.get("label", "");
  form.description = req.form.get("description", "");
  form.rights = req.form.getAll("rights").dup;
  return form;
}
