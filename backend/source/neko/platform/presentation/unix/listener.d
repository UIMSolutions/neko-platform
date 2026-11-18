/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Unix domain socket transport: serves the same router over a socket file
/// instead of TCP — for hosts where the platform must not open a network port
/// (e.g. behind a local reverse proxy, or in an air-gapped domain).
///
///   curl --unix-socket /tmp/neko-platform-secret.sock http://localhost/health
module neko.platform.presentation.unix.listener;

import std.file : exists, getAttributes, remove, mkdirRecurse;
import std.path : dirName;
import core.sys.posix.sys.stat : S_IFMT, S_IFSOCK, chmod;
import std.conv : octal;
import std.string : toStringz;
import vibe.core.log : logInfo;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPListener, HTTPServerSettings, listenHTTP;

@safe:

/// Listen on `path`. A stale socket left by a crashed instance is removed;
/// any other existing file at that path is an error (never delete data).
HTTPListener listenOnUnixSocket(string path, URLRouter router, uint mode = octal!"660") {
  if (path.length == 0 || path[0] != '/')
    throw new Exception("Unix socket path must be absolute: '" ~ path ~ "'");

  () @trusted {
    mkdirRecurse(path.dirName);
    if (path.exists) {
      if ((path.getAttributes & S_IFMT) != S_IFSOCK)
        throw new Exception("Refusing to replace non-socket file " ~ path);
      path.remove;
    }
  }();

  auto settings = new HTTPServerSettings;
  settings.bindAddresses = [path];
  auto listener = listenHTTP(settings, router);
  () @trusted { chmod(path.toStringz, mode); }();
  logInfo("Listening on unix socket %s (mode %o)", path, mode);
  return listener;
}
