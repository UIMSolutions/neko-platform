/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Business exceptions. Each carries an HTTP-like status code so driving
/// adapters can translate it without knowing the concrete type.
module neko.platform.domain.exceptions;

@safe:

public:
  import neko.platform.domain.exceptions.conflict;
  import neko.platform.domain.exceptions.integrity;
  import neko.platform.domain.exceptions.invalidstatetransition;
  import neko.platform.domain.exceptions.notfound;
  import neko.platform.domain.exceptions.platform;
  import neko.platform.domain.exceptions.policyviolation;
  import neko.platform.domain.exceptions.validation;