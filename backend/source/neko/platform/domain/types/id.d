/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.platform.domain.types.id;

import std.algorithm : all, canFind, startsWith;
import std.ascii : isAlphaNum;
import std.string : strip;
import neko.platform.domain.exceptions;

@safe:

/// Strongly typed identifier, so a ServiceId is never passed as a TransferId.
struct Id(string kind) {
  string value;

  bool isEmpty() const pure nothrow {
    return value.length == 0;
  }

  string toString() const pure nothrow {
    return value;
  }
}

alias ServiceId = Id!"service";
alias TransferId = Id!"transfer";
/// Web user account (not UserId: uim.service already defines that name).
alias AccountId = Id!"account";

///
unittest {
  ServiceId sid;
  sid.value = "service-123";
  assert(!sid.isEmpty());

  TransferId tid;
  tid.value = "transfer-456";
  assert(!tid.isEmpty());
}
/// A file of a subaccount's library.
alias FileId = Id!"file";
