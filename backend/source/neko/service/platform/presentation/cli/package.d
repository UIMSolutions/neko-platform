/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Command-line driving adapter. Works on the same data directory as the
/// server, so it can administer a running or a stopped instance.
module neko.service.platform.presentation.cli;

import std.algorithm : map, max, startsWith;
import std.array : array, join;
import std.conv : to;
import std.file : readText, write;
import std.format : format;
import std.process : environment;
import std.stdio : File, stderr, stdout;
import std.string : leftJustify;
import std.typecons : Nullable;
import neko.service.platform.domain;
import neko.service.platform.application.dtos;
import neko.service.platform.infrastructure.container : PlatformContainer;

enum usage = `Usage: platform-<domain> [command] [arguments] [--option=value …]

  serve                               start the HTTP server (default)
  info                                show the effective configuration
  overview                            key figures of this platform instance
  services [list] [--search=] [--status=] [--classification=]
  services show <id>
  services register --name= [--description=] [--classification=] [--url=] [--health=] [--activate]
  services update <id> [--description=] [--url=] [--health=]
  services activate|suspend|retire|check|remove <id>
  check-all                           probe all active services once
  transfers [list]
  transfers show <id>
  transfers export --name= --target= (--payload= | --file=) [--out=]
  transfers document <id> [--out=]    write the transfer document of an outbound package
  transfers import <file>
  help`;

/// Parsed command line: positional words and --key=value options.
struct CliArgs {
  string[] words;
  string[string] options;

  static CliArgs parse(string[] args) {
    CliArgs a;
    foreach (arg; args) {
      if (arg.startsWith("--")) {
        auto body = arg[2 .. $];
        import std.string : indexOf;

        auto eq = body.indexOf('=');
        if (eq < 0)
          a.options[body] = "true";
        else
          a.options[body[0 .. eq]] = body[eq + 1 .. $];
      } else
        a.words ~= arg;
    }
    return a;
  }

  string word(size_t i, string name) const {
    if (i >= words.length)
      throw new ValidationException("Missing argument <" ~ name ~ ">");
    return words[i];
  }

  string opt(string key, string fallback = "") const {
    if (auto v = key in options)
      return *v;
    return fallback;
  }

  Nullable!string optional(string key) const {
    Nullable!string result;
    if (auto v = key in options)
      result = *v;
    return result;
  }

  bool flag(string key) const {
    return opt(key) == "true";
  }
}

/// Run a command; returns the process exit code.
int runCli(PlatformContainer c, string[] args, File output = stdout) {
  auto a = CliArgs.parse(args);
  auto actor = "cli:" ~ environment.get("USER", "unknown");
  try {
    auto command = a.words.length > 0 ? a.words[0] : "help";
    auto sub = a.words.length > 1 ? a.words[1] : "list";
    switch (command) {
    case "help", "--help", "-h":
      output.writeln(usage);
      return 0;
    case "info":
      output.writeln(c.config.toJson(c.domain).toPrettyString);
      return 0;
    case "overview":
      auto o = c.overview.overview();
      output.writefln("Domain        %s (%s)", o.domain, o.environment);
      output.writefln("Export        %s%s", o.canExport ? "yes → " : "no", o.exportTargets.join(", "));
      output.writefln("Import        %s", o.canImport ? "yes" : "no");
      output.writefln("Services      %d (%d active, %d down)", o.serviceCount, o.activeServices, o.servicesDown);
      output.writefln("Transfers     %d (%d out, %d in, %d rejected)", o.transferCount, o.outboundTransfers,
        o.inboundTransfers, o.rejectedTransfers);
      return 0;
    case "check-all":
      output.writefln("Probed %d service(s)", c.health.checkAll());
      return 0;
    case "services":
      return servicesCommand(c, sub, a, actor, output);
    case "transfers":
      return transfersCommand(c, sub, a, actor, output);
    default:
      stderr.writeln("Unknown command '", command, "'\n\n", usage);
      return 2;
    }
  } catch (PlatformException e) {
    stderr.writefln("Error (%d): %s", e.code, e.msg);
    return 1;
  } catch (Exception e) {
    stderr.writeln("Error: ", e.msg);
    return 1;
  }
}

private int servicesCommand(PlatformContainer c, string sub, CliArgs a, string actor, File output) {
  switch (sub) {
  case "list":
    auto items = c.services.list(ServiceQuery(a.opt("search"), a.opt("status"), a.opt("classification")));
    printTable(output, ["ID", "NAME", "CLASS", "STATUS", "HEALTH", "URL"],
      items.map!(s => [s.id, s.name, s.classification, s.status, s.health, s.baseUrl]).array);
    return 0;
  case "show":
    printService(output, c.services.get(a.word(2, "id")));
    return 0;
  case "register":
    auto r = RegisterServiceRequest(a.opt("name"), a.opt("description"), a.opt("classification"),
      a.opt("url"), a.opt("health"), a.flag("activate"));
    printService(output, c.services.register(r, actor));
    return 0;
  case "update":
    auto r = UpdateServiceRequest(a.optional("description"), a.optional("url"), a.optional("health"));
    printService(output, c.services.update(a.word(2, "id"), r, actor));
    return 0;
  case "activate":
    printService(output, c.services.activate(a.word(2, "id"), actor));
    return 0;
  case "suspend":
    printService(output, c.services.suspend(a.word(2, "id"), actor));
    return 0;
  case "retire":
    printService(output, c.services.retire(a.word(2, "id"), actor));
    return 0;
  case "check":
    printService(output, c.health.check(a.word(2, "id")));
    return 0;
  case "remove":
    c.services.remove(a.word(2, "id"), actor);
    output.writeln("Removed.");
    return 0;
  default:
    throw new ValidationException("Unknown services command '" ~ sub ~ "'");
  }
}

private int transfersCommand(PlatformContainer c, string sub, CliArgs a, string actor, File output) {
  switch (sub) {
  case "list":
    printTable(output, ["ID", "NAME", "DIRECTION", "FROM", "TO", "STATUS", "SIZE", "CREATED"],
      c.transfers.list().map!(t => [t.id, t.name, t.direction, t.sourceDomain, t.targetDomain, t.status,
        t.size.to!string, t.createdAt]).array);
    return 0;
  case "show":
    printTransfer(output, c.transfers.get(a.word(2, "id")));
    return 0;
  case "export":
    auto payload = a.opt("payload");
    if (auto file = "file" in a.options)
      payload = readText(*file);
    auto created = c.transfers.exportPackage(ExportPackageRequest(a.opt("name"), a.opt("target"), payload), actor);
    printTransfer(output, created);
    if (auto out_ = "out" in a.options) {
      write(*out_, c.transfers.document(created.id));
      output.writeln("Transfer document written to ", *out_);
    }
    return 0;
  case "document":
    auto doc = c.transfers.document(a.word(2, "id"));
    if (auto out_ = "out" in a.options)
      write(*out_, doc);
    else
      output.writeln(doc);
    return 0;
  case "import":
    auto doc = readText(a.word(2, "file"));
    printTransfer(output, c.transfers.importPackage(ImportPackageRequest(doc), actor));
    return 0;
  default:
    throw new ValidationException("Unknown transfers command '" ~ sub ~ "'");
  }
}

private void printService(File output, ServiceDto s) {
  output.writefln("ID              %s\nName            %s\nDescription     %s\nClassification  %s\n"
      ~ "Status          %s\nHealth          %s (checked %s)\nBase URL        %s\nHealth path     %s\n"
      ~ "Created         %s\nModified        %s",
      s.id, s.name, s.description, s.classification, s.status, s.health,
      s.lastCheckedAt.length ? s.lastCheckedAt : "never", s.baseUrl, s.healthPath, s.createdAt, s.modifiedAt);
}

private void printTransfer(File output, TransferDto t) {
  output.writefln("ID         %s\nName       %s\nDirection  %s (%s → %s)\nStatus     %s%s\nSize       %d bytes\n"
      ~ "SHA-256    %s\nCreated    %s by %s",
      t.id, t.name, t.direction, t.sourceDomain, t.targetDomain, t.status,
      t.reason.length ? " — " ~ t.reason : "", t.size, t.checksum, t.createdAt, t.createdBy);
}

private void printTable(File output, string[] header, string[][] rows) {
  auto widths = header.map!(h => h.length).array;
  foreach (row; rows)
    foreach (i, cell; row)
      widths[i] = max(widths[i], cell.length);
  void line(string[] cells) {
    string text;
    foreach (i, cell; cells)
      text ~= (i + 1 < cells.length ? cell.leftJustify(widths[i] + 2) : cell);
    output.writeln(text);
  }

  line(header);
  foreach (row; rows)
    line(row);
  if (rows.length == 0)
    output.writeln("(none)");
}

///
unittest {
  auto a = CliArgs.parse(["services", "register", "--name=billing", "--activate"]);
  assert(a.words == ["services", "register"] && a.opt("name") == "billing" && a.flag("activate"));
  assert(a.optional("url").isNull);
}
