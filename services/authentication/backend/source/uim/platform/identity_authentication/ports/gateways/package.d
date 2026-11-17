/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Driven ports for security primitives and external systems
/// (password hashing, token signing, one-time passwords, OTP delivery).
module neko.service.authentication.ports.gateways;

public {
  import neko.service.authentication.ports.gateways.password;
  import neko.service.authentication.ports.gateways.secrets;
  import neko.service.authentication.ports.gateways.token;
  import neko.service.authentication.ports.gateways.mfa;
}
