/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The global accounts of the instance (web interface; htmx fragments).
/// Registered only in the default global account: the operator's.
///
///   GET  /accounts                  page                           accounts.manage
///   GET  /accounts/new              create dialog                  accounts.manage
///   POST /accounts                  create (and set it up)         accounts.manage
///   GET  /accounts/:key/edit        settings dialog                accounts.manage
///   POST /accounts/:key             name, host names, description  accounts.manage
///   POST /accounts/:key/delete      unregister (data is kept)      accounts.manage
module neko.platform.presentation.web.accounts;

import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : GlobalAccountEntryRequest;
import neko.platform.domain : GlobalAccountEntry, PlatformException;
import neko.platform.ports.usecases : IManageGlobalAccountsUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.landscape : words;
import neko.platform.presentation.web.support;

@safe:

struct GlobalAccountForm {
  bool existing;
  GlobalAccountEntryRequest values;
  string error;
}

@requiresAuth
class GlobalAccountsWeb {
  private WebGuard guard;
  private IManageGlobalAccountsUseCase accounts;
  private string delegate(GlobalAccountEntry) @safe setUp;

  mixin PageAuthentication;

  /// `setUp` creates the data of a new global account and returns a note for
  /// the operator (e.g. the first administrator's generated password).
  this(WebGuard guard, IManageGlobalAccountsUseCase accounts, string delegate(GlobalAccountEntry) @safe setUp) {
    this.guard = guard;
    this.accounts = accounts;
    this.setUp = setUp;
  }

  @auth(Role.accountsManage) @path("/accounts")
  void getAccounts(PageContext page) {
    page = page.at("Global accounts", "accounts");
    auto list = accounts.list();
    string notice;
    render!("globalaccounts.dt", page, list, notice);
  }

  @auth(Role.accountsManage) @path("/accounts/new")
  void getNew(PageContext page) {
    GlobalAccountForm form;
    render!("globalaccount_dialog.dt", page, form);
  }

  @auth(Role.accountsManage) @path("/accounts")
  void postAccounts(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    auto form = readForm(req, false, req.form.get("key", ""));
    try {
      auto e = accounts.create(form.values, page.user.userName);
      auto note = setUp(e);
      table(res, page, "Global account " ~ e.key ~ " created", false, note);
    } catch (PlatformException ex) {
      form.error = ex.msg;
      render!("globalaccount_dialog.dt", page, form);
    }
  }

  @auth(Role.accountsManage) @path("/accounts/:key/edit")
  void getEdit(PageContext page, HTTPServerResponse res, string _key) {
    try {
      auto e = accounts.get(_key);
      auto form = GlobalAccountForm(true, GlobalAccountEntryRequest(e.key, e.name, e.hosts.dup, e.description));
      render!("globalaccount_dialog.dt", page, form);
    } catch (PlatformException ex)
      res.writeBody(ex.msg, 404, "text/plain; charset=utf-8");
  }

  @auth(Role.accountsManage) @path("/accounts/:key")
  void postAccount(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _key) {
    auto form = readForm(req, true, _key);
    try {
      accounts.update(_key, form.values, page.user.userName);
      table(res, page, "Global account " ~ _key ~ " saved", false, "");
    } catch (PlatformException ex) {
      form.error = ex.msg;
      render!("globalaccount_dialog.dt", page, form);
    }
  }

  @auth(Role.accountsManage) @path("/accounts/:key/delete")
  void postDelete(PageContext page, HTTPServerResponse res, string _key) {
    try {
      auto e = accounts.get(_key);
      accounts.remove(_key, page.user.userName);
      table(res, page, "Global account " ~ _key ~ " unregistered", false, "The data of " ~ _key ~ " stays in "
          ~ e.dataDir ~ "; create a global account with the same key to use it again.");
    } catch (PlatformException ex)
      table(res, page, ex.msg, true, "");
  }

  @noRoute GlobalAccountForm readForm(HTTPServerRequest req, bool existing, string key) {
    return GlobalAccountForm(existing, GlobalAccountEntryRequest(key, req.form.get("name", ""),
      words(req.form.get("hosts", "")), req.form.get("description", "")));
  }

  @noRoute void table(HTTPServerResponse res, PageContext page, string message, bool error, string notice) {
    swapTable(res, "accounts-table", message, error);
    auto list = accounts.list();
    render!("globalaccounts_table.dt", page, list, notice);
  }
}
