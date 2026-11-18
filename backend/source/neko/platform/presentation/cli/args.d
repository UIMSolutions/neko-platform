/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Command line parsing: positional words and --key[=value] options.
module neko.platform.presentation.cli.args;

import std.algorithm : startsWith;
import std.string : indexOf;
import std.typecons : Nullable;
import neko.platform.domain : ValidationException;

@safe:

/// Parsed command line. A bare `--key` is stored as "true"; everything after
/// a lone `--` is positional.
struct CliArgs {
  string[] words;
  string[string] options;

  static CliArgs parse(string[] args) {
    CliArgs a;
    bool positionalOnly;
    foreach (arg; args) {
      if (positionalOnly || !arg.startsWith("--") || arg == "-") {
        a.words ~= arg;
        continue;
      }
      if (arg == "--") {
        positionalOnly = true;
        continue;
      }
      auto body = arg[2 .. $];
      auto eq = body.indexOf('=');
      if (eq < 0)
        a.options[body] = "true";
      else
        a.options[body[0 .. eq]] = body[eq + 1 .. $];
    }
    return a;
  }

  /// Positional word `i`, or a ValidationException naming the missing `<name>`.
  string word(size_t i, string name) const {
    if (i >= words.length)
      throw new ValidationException("Missing argument <" ~ name ~ ">");
    return words[i];
  }

  /// Positional word `i`, or `fallback`.
  string wordOr(size_t i, string fallback) const {
    return i < words.length ? words[i] : fallback;
  }

  string opt(string key, string fallback = "") const {
    if (auto v = key in options)
      return *v;
    return fallback;
  }

  /// Option `key` if given (also when empty) — for partial updates.
  Nullable!string optional(string key) const {
    Nullable!string result;
    if (auto v = key in options)
      result = *v;
    return result;
  }

  bool has(string key) const {
    return (key in options) !is null;
  }

  bool flag(string key) const {
    return opt(key) == "true";
  }
}

///
unittest {
  auto a = CliArgs.parse(["services", "register", "--name=billing", "--activate", "--url="]);
  assert(a.words == ["services", "register"] && a.opt("name") == "billing" && a.flag("activate"));
  assert(a.optional("health").isNull && !a.optional("url").isNull && a.optional("url").get == "");
  assert(a.wordOr(2, "x") == "x");

  auto b = CliArgs.parse(["transfers", "import", "--", "--weird-name.json"]);
  assert(b.words == ["transfers", "import", "--weird-name.json"] && b.options.length == 0);

  bool missing;
  try
    a.word(2, "id");
  catch (ValidationException)
    missing = true;
  assert(missing);
}
