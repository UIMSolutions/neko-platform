/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.provisioning.domain.enumerations.transformations;

import neko.provisioning;

mixin(ShowModule!());

@safe:

/// Which entities a transformation applies to.
enum EntityScope {
  all,
  user,
  group,
}

/// Function applied to a mapped value.
enum MappingFunction {
  none,
  lowerCase,
  upperCase,
  trim,
  constant, /// always the default value
}

/// Comparison of a filter condition (string based, case-insensitive).
enum ConditionOperator {
  equals,
  notEquals,
  contains,
  startsWith,
  endsWith,
  present, /// attribute has a value
  absent, /// attribute is empty or missing
}
