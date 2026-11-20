/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Controller for the unix socket transport: owns the socket's lifecycle
/// (listen, stop, remove the socket file) and reports its state.
///
///   GET /api/v1/socket   {"path", "mode", "listening", "since"}
///
///   auto socket = new UnixSocketController(config.effectiveSocketPath(domain));
///   socket.registerRoutes(router);   // before the static catch-all
///   socket.start(router);
///   scope (exit) socket.stop();
module neko.platform.presentation.unix.controller;

import std.conv : octal;
import std.datetime.systime : Clock, SysTime;
import std.file : exists, getAttributes, remove;
import std.format : format;
import core.sys.posix.sys.stat : S_IFMT, S_IFSOCK;
import vibe.core.log : logInfo, logWarn;
import vibe.data.json;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPListener, HTTPServerErrorPageHandler, HTTPServerRequest, HTTPServerRequestHandler,
  HTTPServerResponse;
import neko.platform.presentation.unix.listener : listenOnUnixSocket;

@safe:

class UnixSocketController {
  private string _path;
  private uint _mode;
  private HTTPListener listener;
  private bool _listening;
  private SysTime since;

  /// `mode` is applied to the socket file (default rw for owner and group).
  this(string path, uint mode = octal!"660") {
    _path = path;
    _mode = mode;
  }

  string path() const { return _path; }
  uint mode() const { return _mode; }
  bool listening() const { return _listening; }

  void registerRoutes(URLRouter router) {
    router.get("/api/v1/socket", &info);
  }

  /// Start serving `handler` (the router, possibly wrapped) on the socket. Throws if already listening, if the
  /// path is not absolute, or if a non-socket file occupies the path.
  /// `errorPages` renders error responses (null = vibe.d default).
  void start(HTTPServerRequestHandler handler, HTTPServerErrorPageHandler errorPages = null,
      ulong maxRequestSize = 0) {
    if (_listening)
      throw new Exception("Unix socket " ~ _path ~ " is already listening");
    listener = listenOnUnixSocket(_path, handler, _mode, errorPages, maxRequestSize);
    _listening = true;
    since = Clock.currTime;
  }

  /// Stop listening and remove the socket file. Safe to call repeatedly.
  void stop() {
    if (!_listening)
      return;
    listener.stopListening();
    _listening = false;
    try {
      () @trusted {
        if (_path.exists && (_path.getAttributes & S_IFMT) == S_IFSOCK)
          _path.remove;
      }();
      logInfo("Unix socket %s closed", _path);
    } catch (Exception e)
      logWarn("Cannot remove unix socket %s: %s", _path, e.msg);
  }

  Json toJson() const {
    auto j = Json.emptyObject;
    j["path"] = _path;
    j["mode"] = format("%04o", _mode);
    j["listening"] = _listening;
    if (_listening)
      j["since"] = since.toISOExtString;
    return j;
  }

  void info(HTTPServerRequest req, HTTPServerResponse res) {
    res.writeJsonBody(toJson);
  }
}

///
unittest {
  auto c = new UnixSocketController("/tmp/neko-test.sock");
  assert(!c.listening && c.mode == octal!"660");
  auto j = c.toJson;
  assert(j["path"].get!string == "/tmp/neko-test.sock");
  assert(j["mode"].get!string == "0660");
  assert(!j["listening"].get!bool && "since" !in j);
  c.stop(); // no-op when not listening
}
