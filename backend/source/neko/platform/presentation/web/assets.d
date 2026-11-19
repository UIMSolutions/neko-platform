/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Front-end assets compiled into the binary (backend/assets), served under
/// /ui/. Isolated domains have no CDN access, and the UI Content-Security-
/// Policy only allows this origin — so Beer CSS, htmx and the icon font ship
/// with the executable. Versions: backend/assets/vendor/README.md.
module neko.platform.presentation.web.assets;

import std.conv : to;
import vibe.http.router : URLRouter;
import vibe.http.server : HTTPServerRequest, HTTPServerResponse;

@safe:

/// [published name, file under backend/assets, content type, long-lived cache]
private enum string[4][] files = [
  ["beer-5.0.3.min.css", "vendor/beer.min.css", "text/css; charset=utf-8", "y"],
  ["htmx-2.0.11.min.js", "vendor/htmx.min.js", "text/javascript; charset=utf-8", "y"],
  ["material-symbols-outlined.woff2", "vendor/material-symbols-outlined.woff2", "font/woff2", "y"],
  ["material-symbols-subset.woff2", "vendor/material-symbols-subset.woff2", "font/woff2", "y"],
  ["app.css", "app.css", "text/css; charset=utf-8", ""],
  ["app.js", "app.js", "text/javascript; charset=utf-8", ""],
];

class AssetsController {
  void registerRoutes(URLRouter router) {
    router.get("/ui/:file", &serve);
  }

  void serve(HTTPServerRequest req, HTTPServerResponse res) @trusted {
    auto name = req.params["file"];
    static foreach (f; files) {
      if (name == f[0]) {
        // Versioned vendor files never change; app files may with each build.
        res.headers["Cache-Control"] = f[3].length ? "public, max-age=31536000, immutable" : "no-cache";
        static immutable content = cast(immutable(ubyte)[]) import(f[1]);
        res.headers["Content-Type"] = f[2];
        res.headers["Content-Length"] = content.length.to!string;
        res.bodyWriter.write(content);
        return;
      }
    }
    // not ours: let the router continue (e.g. to the Fiori app)
  }
}
