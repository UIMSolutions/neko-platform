/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// A file of a subaccount's library (document, image, audio, video, …). The bytes
/// live in a blob store; this entity is the metadata.
module neko.platform.domain.entities.file;

import std.algorithm : endsWith, max;
import std.datetime.systime : SysTime;
import std.path : extension;
import std.string : lastIndexOf, strip, toLower;
import std.utf : byDchar;
import neko.platform.domain.exceptions;
import neko.platform.domain.types;

@safe:

enum FileKind {
  document,
  image,
  audio,
  video,
  archive,
  other,
}

struct StoredFile {
  FileId id;
  /// Key of the subaccount whose library holds the file (and whose folder
  /// in the blob store holds its content).
  string subaccount;
  /// Display and download name ("Price list 2026.pdf").
  string name;
  /// Derived from the name's extension, never taken from the client.
  string contentType;
  FileKind kind;
  long size;
  /// Hex SHA-256 of the content.
  string sha256;
  /// Alt text / caption.
  string description;
  /// Downloadable without signing in (/media/<subaccount>/<id>/<name>).
  bool isPublic;
  string uploadedBy;
  SysTime createdAt;
  SysTime modifiedAt;

  void rename(string name, SysTime now) {
    this.name = sanitizeFileName(name);
    contentType = contentTypeFor(this.name);
    kind = kindOf(contentType);
    modifiedAt = now;
  }

  void describe(string text, SysTime now) {
    auto t = text.strip;
    if (t.length > 500)
      throw new ValidationException("Description exceeds 500 characters");
    description = t;
    modifiedAt = now;
  }

  void publish(bool isPublic, SysTime now) pure nothrow {
    this.isPublic = isPublic;
    modifiedAt = now;
  }

  /// Safe for a browser to show in place: raster images, audio, video, PDF.
  /// Everything else (also SVG, HTML) is only offered as a download.
  bool inlineSafe() const pure nothrow {
    switch (kind) {
    case FileKind.image:
      return contentType != "image/svg+xml";
    case FileKind.audio, FileKind.video:
      return true;
    default:
      return contentType == "application/pdf";
    }
  }
}

/// The last path segment, without control characters and characters that
/// break headers or paths; at most 200 bytes. Throws if nothing is left.
string sanitizeFileName(string name) pure {
  auto slash = max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
  auto base = slash >= 0 ? name[slash + 1 .. $] : name;
  string result;
  foreach (dchar c; base.byDchar) {
    if (c < 0x20 || c == 0x7F || c == '"' || c == '<' || c == '>' || c == '|' || c == ':' || c == '*' || c == '?')
      continue;
    import std.utf : encode;

    char[4] buf;
    auto n = encode(buf, c);
    if (result.length + n > 200)
      break;
    result ~= buf[0 .. n].idup;
  }
  result = result.strip;
  while (result.length && (result[0] == '.' || result[$ - 1] == '.'))
    result = result[0] == '.' ? result[1 .. $].strip : result[0 .. $ - 1].strip;
  if (result.length == 0)
    throw new ValidationException("'" ~ name ~ "' is not a usable file name");
  return result;
}

/// Content type by extension; unknown (and active content such as HTML or
/// JavaScript) → application/octet-stream.
string contentTypeFor(string name) pure {
  switch (name.extension.toLower) {
  case ".pdf":
    return "application/pdf";
  case ".txt", ".log":
    return "text/plain; charset=utf-8";
  case ".md":
    return "text/markdown; charset=utf-8";
  case ".csv":
    return "text/csv; charset=utf-8";
  case ".json":
    return "application/json";
  case ".rtf":
    return "application/rtf";
  case ".doc":
    return "application/msword";
  case ".docx":
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  case ".xls":
    return "application/vnd.ms-excel";
  case ".xlsx":
    return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  case ".ppt":
    return "application/vnd.ms-powerpoint";
  case ".pptx":
    return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
  case ".odt":
    return "application/vnd.oasis.opendocument.text";
  case ".ods":
    return "application/vnd.oasis.opendocument.spreadsheet";
  case ".odp":
    return "application/vnd.oasis.opendocument.presentation";
  case ".epub":
    return "application/epub+zip";
  case ".png":
    return "image/png";
  case ".jpg", ".jpeg":
    return "image/jpeg";
  case ".gif":
    return "image/gif";
  case ".webp":
    return "image/webp";
  case ".avif":
    return "image/avif";
  case ".bmp":
    return "image/bmp";
  case ".ico":
    return "image/x-icon";
  case ".svg":
    return "image/svg+xml";
  case ".mp3":
    return "audio/mpeg";
  case ".wav":
    return "audio/wav";
  case ".ogg", ".oga":
    return "audio/ogg";
  case ".opus":
    return "audio/opus";
  case ".flac":
    return "audio/flac";
  case ".m4a":
    return "audio/mp4";
  case ".aac":
    return "audio/aac";
  case ".mp4", ".m4v":
    return "video/mp4";
  case ".webm":
    return "video/webm";
  case ".ogv":
    return "video/ogg";
  case ".mov":
    return "video/quicktime";
  case ".mkv":
    return "video/x-matroska";
  case ".zip":
    return "application/zip";
  case ".gz", ".tgz":
    return "application/gzip";
  case ".tar":
    return "application/x-tar";
  case ".7z":
    return "application/x-7z-compressed";
  default:
    return "application/octet-stream";
  }
}

FileKind kindOf(string contentType) pure nothrow {
  import std.algorithm : startsWith;

  if (contentType.startsWith("image/"))
    return FileKind.image;
  if (contentType.startsWith("audio/"))
    return FileKind.audio;
  if (contentType.startsWith("video/"))
    return FileKind.video;
  switch (contentType) {
  case "application/zip", "application/gzip", "application/x-tar", "application/x-7z-compressed":
    return FileKind.archive;
  case "application/octet-stream":
    return FileKind.other;
  default:
    return FileKind.document;
  }
}

///
unittest {
  assert(sanitizeFileName("C:\\Users\\me\\Price list 2026.PDF") == "Price list 2026.PDF");
  assert(sanitizeFileName("../../etc/passwd") == "passwd" && sanitizeFileName(".hidden.") == "hidden");
  assert(sanitizeFileName("a\"b\r\n.txt") == "ab.txt" && sanitizeFileName("Grüße.txt") == "Grüße.txt");
  foreach (bad; ["", "...", "dir/", "\x01"]) {
    bool failed;
    try
      sanitizeFileName(bad);
    catch (ValidationException)
      failed = true;
    assert(failed, bad);
  }

  StoredFile f;
  f.rename("Logo.SVG", SysTime.init);
  assert(f.kind == FileKind.image && !f.inlineSafe);
  f.rename("clip.webm", SysTime.init);
  assert(f.kind == FileKind.video && f.inlineSafe);
  f.rename("page.html", SysTime.init);
  assert(f.contentType == "application/octet-stream" && f.kind == FileKind.other && !f.inlineSafe);
  f.rename("report.pdf", SysTime.init);
  assert(f.kind == FileKind.document && f.inlineSafe);
  assert(kindOf(contentTypeFor("x.tgz")) == FileKind.archive);
}
