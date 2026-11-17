/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Uniform construction of use case results.
module neko.service.management.application.services.results;

import neko.service.management;

mixin(ShowModule!());

@safe:

UsecaseResult ok(string id, string message = "") {
  return UsecaseResult(true, id, message, ResultCode.ok);
}

UsecaseResult created(string id, string message = "") {
  return UsecaseResult(true, id, message, ResultCode.created);
}

UsecaseResult invalid(string message) {
  return UsecaseResult(false, "", message, ResultCode.invalid);
}

UsecaseResult notFound(string what) {
  return UsecaseResult(false, "", what ~ " not found", ResultCode.notFound);
}

UsecaseResult conflict(string message) {
  return UsecaseResult(false, "", message, ResultCode.conflict);
}

UsecaseResult violation(string message) {
  return UsecaseResult(false, "", message, ResultCode.ruleViolation);
}

/// Run a domain operation; a ManagementException becomes a failed result.
UsecaseResult guarded(scope UsecaseResult delegate() @safe action) {
  try
    return action();
  catch (ManagementException e)
    return UsecaseResult(false, "", e.msg, e.code);
}

/// The acting user, or "system" if unknown.
UserId actor(UserId user) {
  return user.isEmpty ? UserId("system") : user;
}

///
unittest {
  mixin(ShowTest!("results"));

  auto r = guarded(delegate UsecaseResult() @safe { throw new LimitExceeded("full"); });
  assert(!r.isSuccess && r.code == ResultCode.ruleViolation && r.message == "full");
  assert(notFound("Subaccount").code == 404);
  assert(actor(UserId("")).value == "system");
}
