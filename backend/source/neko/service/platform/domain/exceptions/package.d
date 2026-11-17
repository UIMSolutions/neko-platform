/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Business exceptions. Each carries an HTTP-like status code so driving
/// adapters can translate it without knowing the concrete type.
module neko.service.platform.domain.exceptions;

@safe:

public:
  import neko.service.platform.domain.exceptions.conflict;
  import neko.service.platform.domain.exceptions.integrity;
  import neko.service.platform.domain.exceptions.invalidstatetransition;
  import neko.service.platform.domain.exceptions.notfound;
  import neko.service.platform.domain.exceptions.platform;
  import neko.service.platform.domain.exceptions.policyviolation;
  import neko.service.platform.domain.exceptions.validation;