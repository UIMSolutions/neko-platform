/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Serves the NEKO Fiori app from frontend/ for local development.
module neko.platform.presentation.web.frontend;

import std.file : exists, isDir;
import std.path : buildPath, dirName;
import vibe.http.fileserver : serveStaticFiles;
import vibe.http.router : URLRouter;

@safe:

/// Serves the UI5 app at "/". Register LAST: it is a catch-all for GET.
/// The UI5 manifest uses relative URIs, so the same files work behind the approuter.
class FrontendController {
  private string directory;

  /// `configured` = "" → first of frontend/dist (self-contained build incl. UI5),
  /// frontend/, ../frontend/dist, ../frontend, <exe>/../../frontend[/dist] that has an index.html
  /// "none" switches serving off (e.g. on Cloud Foundry, where the approuter serves the app).
  this(string configured) {
    if (configured == "none")
      directory = "";
    else
      directory = configured.length > 0 ? configured : detect();
  }

  string location() const {
    return directory;
  }

  bool available() const {
    return directory.length > 0 && (() @trusted => directory.exists && directory.isDir
        && buildPath(directory, "index.html").exists)();
  }

  void registerRoutes(URLRouter router) {
    if (available)
      router.get("*", serveStaticFiles(directory));
  }

  private static string detect() {
    string[] roots = [".", ".."];
    try {
      import std.file : thisExePath;

      roots ~= buildPath((() @trusted => thisExePath.dirName)(), "..", "..");
    } catch (Exception) {
    }
    string[] candidates;
    foreach (root; roots)
      candidates ~= [buildPath(root, "frontend", "dist"), buildPath(root, "frontend")];
    foreach (c; candidates)
      if ((() @trusted => buildPath(c, "index.html").exists)())
        return c;
    return "";
  }
}
