/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Group nesting rules: cycle detection and transitive memberships.
module neko.directory.domain.services.membership;

import neko.directory;

mixin(ShowModule!());

@safe:

/// True if adding `memberGroup` to `parentGroup` would create a cycle, i.e. if
/// `parentGroup` is reachable from `memberGroup` through nested members.
bool createsCycle(string parentGroup, string memberGroup, scope const(string)[] delegate(string) @safe childGroups) {
  if (parentGroup == memberGroup)
    return true;
  bool[string] seen;
  string[] queue = [memberGroup];
  while (queue.length > 0) {
    auto current = queue[0];
    queue = queue[1 .. $];
    if (current in seen)
      continue;
    seen[current] = true;
    foreach (child; childGroups(current)) {
      if (child == parentGroup)
        return true;
      queue ~= child;
    }
  }
  return false;
}

/// Groups reachable upwards from `directGroups` (excluding the direct ones),
/// given a function returning the parent groups of a group.
string[] ancestorGroups(const string[] directGroups, scope const(string)[] delegate(string) @safe parentGroups) {
  bool[string] seen;
  foreach (g; directGroups)
    seen[g] = true;
  string[] result;
  string[] queue = directGroups.dup;
  while (queue.length > 0) {
    auto current = queue[0];
    queue = queue[1 .. $];
    foreach (parent; parentGroups(current)) {
      if (parent in seen)
        continue;
      seen[parent] = true;
      result ~= parent;
      queue ~= parent;
    }
  }
  return result;
}

///
unittest {
  // a ⊃ b ⊃ c
  string[][string] children = ["a": ["b"], "b": ["c"], "c": []];
  string[][string] parents = ["a": [], "b": ["a"], "c": ["b"]];
  const(string)[] kids(string g) { return children.get(g, null); }
  const(string)[] ups(string g) { return parents.get(g, null); }
  assert(createsCycle("c", "a", &kids)); // c ⊃ a would close the loop
  assert(!createsCycle("a", "c", &kids));
  assert(createsCycle("a", "a", &kids));
  assert(ancestorGroups(["c"], &ups) == ["b", "a"]);
}
