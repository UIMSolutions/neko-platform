/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// CLI rendering: aligned tables and detail views for humans, or JSON
/// (same field names as the REST API) with --json.
module neko.platform.presentation.cli.output;

import std.algorithm : map, max;
import std.array : array, join;
import std.conv : to;
import std.stdio : File;
import std.string : leftJustify;
import vibe.data.json : Json, serializeToJson;
import neko.platform.application.dtos;

class CliOutput {
  File file;
  bool json;

  this(File file, bool json = false) {
    this.file = file;
    this.json = json;
  }

  void message(string text) {
    if (json)
      file.writeln(Json(["message": Json(text)]).toPrettyString);
    else
      file.writeln(text);
  }

  void raw(string text) {
    file.writeln(text);
  }

  void value(Json j) {
    file.writeln(j.toPrettyString);
  }

  void overview(OverviewDto o) {
    if (json)
      return value(serializeToJson(o));
    file.writefln("Domain        %s (%s)", o.domain, o.environment);
    file.writefln("Export        %s%s", o.canExport ? "yes → " : "no", o.exportTargets.join(", "));
    file.writefln("Import        %s", o.canImport ? "yes" : "no");
    file.writefln("Services      %d (%d active, %d down)", o.serviceCount, o.activeServices, o.servicesDown);
    file.writefln("Transfers     %d (%d out, %d in, %d rejected)", o.transferCount, o.outboundTransfers,
      o.inboundTransfers, o.rejectedTransfers);
  }

  void services(ServiceDto[] items) {
    if (json)
      return value(serializeToJson(items));
    table(["ID", "NAME", "CLASS", "STATUS", "HEALTH", "URL"],
      items.map!(s => [s.id, s.name, s.classification, s.status, s.health, s.baseUrl]).array);
  }

  void service(ServiceDto s) {
    if (json)
      return value(serializeToJson(s));
    file.writefln("ID              %s\nName            %s\nDescription     %s\nClassification  %s\n"
        ~ "Status          %s\nHealth          %s (checked %s)\nBase URL        %s\nHealth path     %s\n"
        ~ "Created         %s\nModified        %s",
        s.id, s.name, s.description, s.classification, s.status, s.health,
        s.lastCheckedAt.length ? s.lastCheckedAt : "never", s.baseUrl, s.healthPath, s.createdAt, s.modifiedAt);
  }

  void transfers(TransferDto[] items) {
    if (json)
      return value(serializeToJson(items));
    table(["ID", "NAME", "DIRECTION", "FROM", "TO", "STATUS", "SIZE", "CREATED"],
      items.map!(t => [t.id, t.name, t.direction, t.sourceDomain, t.targetDomain, t.status,
        t.size.to!string, t.createdAt]).array);
  }

  void transfer(TransferDto t) {
    if (json)
      return value(serializeToJson(t));
    file.writefln("ID         %s\nName       %s\nDirection  %s (%s → %s)\nStatus     %s%s\nSize       %d bytes\n"
        ~ "SHA-256    %s\nCreated    %s by %s",
        t.id, t.name, t.direction, t.sourceDomain, t.targetDomain, t.status,
        t.reason.length ? " — " ~ t.reason : "", t.size, t.checksum, t.createdAt, t.createdBy);
  }

  /// Columns padded to the widest cell; "(none)" for an empty table.
  void table(string[] header, string[][] rows) {
    auto widths = header.map!(h => h.length).array;
    foreach (row; rows)
      foreach (i, cell; row)
        widths[i] = max(widths[i], cell.length);
    void line(string[] cells) {
      string text;
      foreach (i, cell; cells)
        text ~= (i + 1 < cells.length ? cell.leftJustify(widths[i] + 2) : cell);
      file.writeln(text);
    }

    line(header);
    foreach (row; rows)
      line(row);
    if (rows.length == 0)
      file.writeln("(none)");
  }
}
