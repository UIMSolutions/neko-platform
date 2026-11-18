/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for security primitives and external systems
/// (password hashing, token signing, one-time passwords, OTP delivery).
module neko.authentication.ports.gateways;

public {
  import neko.authentication.ports.gateways.password;
  import neko.authentication.ports.gateways.secrets;
  import neko.authentication.ports.gateways.token;
  import neko.authentication.ports.gateways.mfa;
}
