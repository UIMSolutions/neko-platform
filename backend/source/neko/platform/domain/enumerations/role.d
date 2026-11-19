/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Roles of web user accounts.
module neko.platform.domain.enumerations.role;

@safe:

/// What a signed-in web user may do.
///   viewer  read the status pages
///   admin   additionally manage user accounts
enum UserRole {
  viewer,
  admin
}
