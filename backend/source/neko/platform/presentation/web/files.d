/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The file libraries of the subaccounts (web interface; htmx fragments as
/// for users).
///
///   GET  /files?subaccount=&kind=   page                          files.read
///   GET  /files/:id/view            show in place (safe types)    files.read
///   GET  /files/:id/download        download                      files.read
///   POST /files/upload              upload (multipart, several)   files.manage
///   GET  /files/:id/edit            edit dialog                   files.manage
///   POST /files/:id                 rename, describe, publish     files.manage
///   POST /files/:id/delete          remove                        files.manage
///
/// Only libraries of subaccounts the signed-in user reaches are shown (the
/// use case answers 404 for others).
module neko.platform.presentation.web.files;

import std.algorithm : canFind, filter;
import std.array : array;
import std.conv : to;
import std.typecons : nullable;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;
import vibe.http.common : HTTPStatusException;
import vibe.web.auth;
import vibe.web.web : noRoute, path, render;
import neko.platform.application.dtos : FileContent, FileDto, SubaccountStorageDto, UpdateFileRequest,
  UploadFileRequest, byteSize;
import neko.platform.domain : NotFoundException, PlatformException;
import neko.platform.ports.usecases : IManageFilesUseCase;
import neko.platform.presentation.web.guard;
import neko.platform.presentation.web.support;

@safe:

/// Filter of the file table.
struct FileView {
  /// The subaccount whose library is shown.
  string subaccount;
  /// "" = all kinds
  string kind;
  string error;
}

/// Values of the edit dialog.
struct FileForm {
  FileDto file;
  string name;
  string description;
  bool isPublic;
  string error;
}

@requiresAuth
class FilesWeb {
  private WebGuard guard;
  private IManageFilesUseCase files;
  private long maxUploadBytes;

  mixin PageAuthentication;

  this(WebGuard guard, IManageFilesUseCase files, long maxUploadBytes) {
    this.guard = guard;
    this.files = files;
    this.maxUploadBytes = maxUploadBytes;
  }

  @auth(Role.filesRead) @path("/files")
  void getFiles(PageContext page, HTTPServerResponse res, string subaccount = "", string kind = "") {
    page = page.at("Files", "files");
    auto libraries = files.libraries(page.user.userName);
    FileView view;
    view.subaccount = chooseLibrary(libraries, subaccount);
    view.kind = kind;
    auto list = load(page, view);
    auto limit = byteSize(maxUploadBytes);
    render!("files.dt", page, libraries, view, list, limit);
  }

  @auth(Role.filesRead) @path("/files/:id/view")
  void getView(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    auto content = open(page, _id);
    sendStoredFile(req, res, content, content.file.inline, false);
  }

  @auth(Role.filesRead) @path("/files/:id/download")
  void getDownload(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    sendStoredFile(req, res, open(page, _id), false, false);
  }

  @auth(Role.filesManage) @path("/files/upload")
  void postUpload(PageContext page, HTTPServerRequest req, HTTPServerResponse res) {
    FileView view;
    view.subaccount = req.form.get("subaccount", "");
    view.kind = req.form.get("kind", "");
    auto isPublic = req.form.get("isPublic", "") == "on";
    auto description = req.form.get("description", "");
    string[] done, failed;
    () @trusted {
      foreach (field, part; req.files.byKeyValue) {
        if (field != "files" || part.filename.name.length == 0)
          continue;
        UploadFileRequest r;
        r.subaccount = view.subaccount;
        r.name = part.filename.name;
        r.sourcePath = part.tempPath.toString;
        r.description = description;
        r.isPublic = isPublic;
        try
          done ~= files.upload(r, page.user.userName).name;
        catch (PlatformException e)
          failed ~= e.msg;
      }
    }();
    if (done.length == 0 && failed.length == 0)
      failed ~= "Choose at least one file";
    auto message = done.length == 1 ? "Uploaded " ~ done[0] : done.length ? "Uploaded " ~ done.length.to!string
      ~ " files" : "";
    if (failed.length)
      message = (message.length ? message ~ "; " : "") ~ failed[0]
        ~ (failed.length > 1 ? " (and " ~ (failed.length - 1).to!string ~ " more)" : "");
    table(res, page, view, message, failed.length > 0);
  }

  @auth(Role.filesManage) @path("/files/:id/edit")
  void getEdit(PageContext page, HTTPServerResponse res, string _id) {
    FileDto file;
    if (!find(res, page, _id, file))
      return;
    auto form = FileForm(file, file.name, file.description, file.isPublic);
    render!("file_dialog.dt", page, form);
  }

  @auth(Role.filesManage) @path("/files/:id")
  void postFile(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    FileDto file;
    if (!find(res, page, _id, file))
      return;
    auto form = FileForm(file, req.form.get("name", ""), req.form.get("description", ""),
      req.form.get("isPublic", "") == "on");
    UpdateFileRequest r;
    r.name = nullable(form.name);
    r.description = nullable(form.description);
    r.isPublic = nullable(form.isPublic);
    try {
      auto changed = files.update(file.id, r, page.user.userName);
      table(res, page, FileView(changed.subaccount), changed.name ~ " saved", false);
    } catch (PlatformException e) {
      form.error = e.msg;
      render!("file_dialog.dt", page, form);
    }
  }

  @auth(Role.filesManage) @path("/files/:id/delete")
  void postDelete(PageContext page, HTTPServerRequest req, HTTPServerResponse res, string _id) {
    FileDto file;
    if (!find(res, page, _id, file))
      return;
    auto view = FileView(file.subaccount, req.form.get("kind", ""));
    try {
      files.remove(file.id, page.user.userName);
      table(res, page, view, file.name ~ " removed", false);
    } catch (PlatformException e)
      table(res, page, view, e.msg, true);
  }

  /// The refreshed table, a toast and "close dialog".
  @noRoute void table(HTTPServerResponse res, PageContext page, FileView view, string message, bool error) {
    swapTable(res, "files-table", message, error);
    auto list = load(page, view);
    render!("files_table.dt", page, view, list);
  }

  @noRoute FileDto[] load(PageContext page, ref FileView view) {
    if (view.subaccount.length == 0)
      return null;
    try {
      auto all = files.list(view.subaccount, page.user.userName);
      return view.kind.length ? all.filter!(f => f.kind == view.kind).array : all;
    } catch (PlatformException e) {
      view.error = e.msg;
      return null;
    }
  }

  @noRoute bool find(HTTPServerResponse res, PageContext page, string id, out FileDto file) {
    try {
      file = files.get(id, page.user.userName);
      return true;
    } catch (PlatformException e) {
      res.writeBody(e.msg, 404, "text/plain; charset=utf-8"); // shown as a toast
      return false;
    }
  }

  @noRoute FileContent open(PageContext page, string id) {
    try
      return files.open(id, page.user.userName);
    catch (NotFoundException e)
      throw new HTTPStatusException(404, "There is no such file (or it belongs to a subaccount you do not work in).");
  }
}

/// The requested library if the user may see it, else the first one.
private string chooseLibrary(const(SubaccountStorageDto)[] list, string wanted) {
  foreach (s; list)
    if (s.subaccount == wanted)
      return s.subaccount;
  return list.length ? list[0].subaccount : "";
}

/// Send a stored file. Only types that are safe to render are sent `inline`;
/// a strict policy keeps uploaded content from running anything.
void sendStoredFile(scope HTTPServerRequest req, scope HTTPServerResponse res, FileContent content, bool inline,
    bool cacheable) {
  import vibe.core.path : NativePath;
  import vibe.http.fileserver : sendFile;

  auto f = content.file;
  res.headers["Content-Type"] = f.contentType;
  res.headers["X-Content-Type-Options"] = "nosniff";
  // PDF viewers need a plugin, which a sandbox forbids.
  res.headers["Content-Security-Policy"] = "default-src 'none'; img-src 'self'; media-src 'self'; "
    ~ "style-src 'unsafe-inline'" ~ (f.contentType == "application/pdf" ? "" : "; sandbox");
  res.headers["Content-Disposition"] = contentDisposition(inline && f.inline ? "inline" : "attachment", f.name);
  res.headers["Cache-Control"] = cacheable ? "public, max-age=300" : "private, no-cache";
  if (content.localPath.length)
    sendFile(req, res, NativePath(content.localPath));
  else
    res.writeBody(content.data, f.contentType);
}

/// `attachment; filename="Gruse.txt"; filename*=UTF-8''Gr%C3%BC%C3%9Fe.txt`
string contentDisposition(string type, string name) {
  import std.uri : encodeComponent;

  string ascii;
  foreach (char c; asciiOnly(name))
    ascii ~= c == '"' || c == '\\' ? '_' : c;
  return type ~ `; filename="` ~ ascii ~ `"; filename*=UTF-8''` ~ (() @trusted => encodeComponent(name))();
}

///
unittest {
  assert(contentDisposition("inline", "a.png") == `inline; filename="a.png"; filename*=UTF-8''a.png`);
  assert(contentDisposition("attachment", "Grüße.txt") == `attachment; filename="Gr??e.txt"; filename*=UTF-8''Gr%C3%BC%C3%9Fe.txt`);
}
