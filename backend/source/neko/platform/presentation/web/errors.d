/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Error pages. vibe.web.auth answers a missing access right with 403; htmx
/// requests get the message as plain text (shown as a toast by app.js), the
/// browser a Tabler page.
module neko.platform.presentation.web.errors;

import vibe.http.server : HTTPServerErrorInfo, HTTPServerRequest, HTTPServerResponse, render;
import vibe.http.status : httpStatusText;
import neko.platform.presentation.http : writeError;
import neko.platform.presentation.web.guard;

@safe:

/// For HTTPServerSettings.errorPageHandler. Requests for paths of which
/// `isApi` says true get the JSON error format of the REST/OData adapters.
auto webErrorPages(WebGuard guard, bool delegate(string path) @safe isApi) {
  return delegate(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error) @safe {
    auto code = error.code;
    if (isApi(req.requestPath.toString)) {
      writeError(res, code, httpStatusText(code), error.message.length ? error.message : httpStatusText(code));
      return;
    }
    auto message = errorMessage(code, error.message);
    if (req.headers.get("HX-Request", "") == "true") {
      res.writeBody(message, code, "text/plain; charset=utf-8");
      return;
    }
    auto page = guard.anonymous(code == 403 ? "Access denied" : code == 404 ? "Not found" : "Error");
    res.statusCode = code;
    res.render!("error.dt", page, code, message);
  };
}

/// Human wording for the generic messages of vibe.d.
string errorMessage(int code, string message) pure {
  if (code == 403 && (message.length == 0 || message == "Not allowed to access this resource."))
    return "Your roles do not grant the access right needed for this. Ask an administrator.";
  if (code == 404)
    return "There is no page at this address.";
  return message.length ? message : "The request could not be processed.";
}

///
unittest {
  assert(errorMessage(403, "Not allowed to access this resource.")[0 .. 10] == "Your roles");
  assert(errorMessage(400, "Missing field") == "Missing field");
}
