/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The file library of each subaccount: metadata in a repository, content
/// in a blob store (one folder per subaccount). Who reaches a library:
/// see access.mayAccessSubaccount. Uploads need the service "files" to be
/// assigned to the subaccount.
module neko.platform.application.usecases.manage_files;

import std.algorithm : canFind, map, sort;
import std.array : array;
import std.string : strip, toLower;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.application.usecases.access;
import neko.platform.ports;

@safe:

/// Key of the service whose rights cover the libraries.
enum filesService = "files";

/// Upload limits (configuration).
struct FileLimits {
  /// Per file.
  long maxFileBytes = 50 * 1024 * 1024;
  /// Per subaccount; 0 = no quota.
  long subaccountQuotaBytes = 0;
}

class ManageFilesUseCase : IManageFilesUseCase {
  private IFileRepository files;
  private ILandscapeRepository landscape;
  private IBlobStore blobs;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  private FileLimits limits;

  this(IFileRepository files, ILandscapeRepository landscape, IBlobStore blobs, IEventPublisher events, IClock clock,
      IIdGenerator ids, FileLimits limits = FileLimits.init) {
    this.files = files;
    this.landscape = landscape;
    this.blobs = blobs;
    this.events = events;
    this.clock = clock;
    this.ids = ids;
    this.limits = limits;
  }

  FileDto[] list(string subaccount, string actor) {
    auto s = requireSubaccount(subaccount, actor);
    auto list = files.ofSubaccount(s.key);
    list.sort!((a, b) => a.createdAt > b.createdAt || (a.createdAt == b.createdAt && a.name < b.name));
    return list.map!(f => f.toDto).array;
  }

  FileDto get(string id, string actor) {
    return load(id, actor).toDto;
  }

  FileDto upload(UploadFileRequest request, string actor) {
    auto s = requireSubaccount(request.subaccount, actor);
    if (!s.allowsService(filesService))
      throw new PolicyViolationException("The service " ~ filesService ~ " is not assigned to the subaccount " ~ s.key
          ~ "; assign it under Service assignments first");
    auto key = s.key;
    auto now = clock.now;
    StoredFile file;
    file.id = FileId(ids.newId);
    file.subaccount = key;
    file.rename(request.name, now);
    file.describe(request.description, now);
    file.isPublic = request.isPublic;
    file.uploadedBy = actor;
    file.createdAt = now;

    BlobInfo info = request.sourcePath.length ? blobs.putFile(key, file.id.value, request.sourcePath)
      : blobs.put(key, file.id.value, request.data);
    scope (failure)
      blobs.remove(key, file.id.value);
    if (info.size == 0)
      throw new ValidationException("The file '" ~ file.name ~ "' is empty");
    if (info.size > limits.maxFileBytes)
      throw new ValidationException("The file '" ~ file.name ~ "' has " ~ byteSize(info.size)
          ~ "; at most " ~ byteSize(limits.maxFileBytes) ~ " are allowed");
    if (limits.subaccountQuotaBytes > 0) {
      long used;
      foreach (f; files.ofSubaccount(key))
        used += f.size;
      if (used + info.size > limits.subaccountQuotaBytes)
        throw new PolicyViolationException("The subaccount " ~ key ~ " would exceed its quota of "
            ~ byteSize(limits.subaccountQuotaBytes) ~ " (" ~ byteSize(used) ~ " used)");
    }
    file.size = info.size;
    file.sha256 = info.sha256;
    files.save(file);
    emit("file.uploaded", file.id.value, actor, "Uploaded " ~ file.name ~ " (" ~ byteSize(file.size)
        ~ ") to subaccount " ~ key ~ (file.isPublic ? ", public" : ""));
    return file.toDto;
  }

  FileDto update(string id, UpdateFileRequest request, string actor) {
    auto file = load(id, actor);
    auto now = clock.now;
    if (!request.name.isNull)
      file.rename(request.name.get, now);
    if (!request.description.isNull)
      file.describe(request.description.get, now);
    auto published = !request.isPublic.isNull && request.isPublic.get != file.isPublic;
    if (!request.isPublic.isNull)
      file.publish(request.isPublic.get, now);
    files.save(file);
    emit(published ? (file.isPublic ? "file.published" : "file.withdrawn") : "file.changed", file.id.value, actor,
      (published ? (file.isPublic ? "Published " : "Withdrew ") : "Changed ") ~ file.name ~ " of subaccount "
        ~ file.subaccount);
    return file.toDto;
  }

  void remove(string id, string actor) {
    auto file = load(id, actor);
    files.remove(file.id);
    blobs.remove(file.subaccount, file.id.value);
    emit("file.removed", file.id.value, actor, "Removed " ~ file.name ~ " from subaccount " ~ file.subaccount);
  }

  FileContent open(string id, string actor) {
    return content(load(id, actor));
  }

  bool tryOpenPublic(string subaccount, string id, out FileContent result) {
    StoredFile file;
    if (!files.tryGet(FileId(id.strip), file) || !file.isPublic || file.subaccount != subaccount)
      return false;
    Subaccount s;
    if (!landscape.load().trySubaccount(subaccount, s))
      return false;
    result = content(file);
    return true;
  }

  StorageDto storage() {
    StorageDto d;
    auto all = files.all;
    auto l = landscape.load();
    string[] known;
    foreach (s; l.subaccounts) {
      known ~= s.key;
      d.subaccounts ~= usageOf(all, s.key, s.name);
    }
    string[] orphans;
    foreach (f; all)
      if (!known.canFind(f.subaccount) && !orphans.canFind(f.subaccount))
        orphans ~= f.subaccount;
    foreach (o; orphans.sort.array)
      d.subaccounts ~= usageOf(all, o, o ~ " (removed)");
    foreach (u; d.subaccounts) {
      d.files += u.files;
      d.bytes += u.bytes;
    }
    d.available = blobs.available;
    d.location = blobs.describe;
    return d;
  }

  SubaccountStorageDto[] libraries(string actor) {
    auto all = files.all;
    auto l = landscape.load();
    SubaccountStorageDto[] list;
    foreach (s; l.subaccounts)
      if (mayAccessSubaccount(l, actor, s.key))
        list ~= usageOf(all, s.key, s.name);
    return list;
  }

  private static SubaccountStorageDto usageOf(const(StoredFile)[] all, string key, string name) {
    auto u = SubaccountStorageDto(key, name);
    foreach (f; all)
      if (f.subaccount == key) {
        u.files++;
        u.bytes += f.size;
      }
    return u;
  }

  private FileContent content(const StoredFile file) {
    FileContent c;
    c.file = file.toDto;
    c.localPath = blobs.localPath(file.subaccount, file.id.value);
    if (c.localPath.length == 0)
      c.data = blobs.get(file.subaccount, file.id.value).idup;
    return c;
  }

  /// The subaccount, if it exists and `actor` reaches it; libraries outside
  /// its reach do not exist for it.
  private Subaccount requireSubaccount(string key, string actor) {
    auto k = key.strip.toLower;
    auto l = landscape.load();
    Subaccount s;
    if (k.length == 0 || !l.trySubaccount(k, s) || !mayAccessSubaccount(l, actor, k))
      throw new NotFoundException("Subaccount", key.strip);
    return s;
  }

  private StoredFile load(string id, string actor) {
    StoredFile file;
    if (!files.tryGet(FileId(id.strip), file) || !mayAccessSubaccount(landscape.load(), actor, file.subaccount))
      throw new NotFoundException("File", id);
    return file;
  }

  private void emit(string type, string subject, string actor, string message) {
    events.publish(PlatformEvent(type, subject, actor, message, clock.now));
  }
}

version (unittest) {
  import std.typecons : nullable;
  import neko.platform.application.services : FixedClock, SequentialIds;
  import neko.platform.application.usecases.manage_landscape : FakeLandscape;
  import neko.platform.application.usecases.manage_users : fails, NoEvents;
  import std.datetime.date : DateTime;
  import std.datetime.systime : SysTime;
  import std.datetime.timezone : UTC;

  class FakeFiles : IFileRepository {
    StoredFile[string] items;

    StoredFile[] all() {
      return items.values;
    }

    StoredFile[] ofSubaccount(string subaccount) {
      StoredFile[] r;
      foreach (f; items)
        if (f.subaccount == subaccount)
          r ~= f;
      return r;
    }

    bool tryGet(FileId id, out StoredFile f) {
      if (auto p = id.value in items) {
        f = *p;
        return true;
      }
      return false;
    }

    void save(StoredFile f) {
      items[f.id.value] = f;
    }

    bool remove(FileId id) {
      return items.remove(id.value);
    }
  }

  class FakeBlobs : IBlobStore {
    immutable(ubyte)[][string] data;

    BlobInfo putFile(string folder, string id, string source) {
      return put(folder, id, cast(const(ubyte)[]) source); // the "path" is the content
    }

    BlobInfo put(string folder, string id, const(ubyte)[] bytes) {
      data[folder ~ "/" ~ id] = bytes.idup;
      return BlobInfo(cast(long) bytes.length, "sha");
    }

    string localPath(string folder, string id) {
      return "";
    }

    ubyte[] get(string folder, string id) {
      if (auto p = (folder ~ "/" ~ id) in data)
        return (*p).dup;
      return null;
    }

    bool remove(string folder, string id) {
      return data.remove(folder ~ "/" ~ id);
    }

    long usage(string folder) {
      return 0;
    }

    long available() {
      return -1;
    }

    string describe() {
      return "fake";
    }
  }

  struct FileFixture {
    FakeLandscape landscape;
    FakeFiles fileRepo;
    FakeBlobs blobs;
    ManageFilesUseCase files;
  }

  /// Subaccounts "main" (bob in its user group) and "blog" (ann administers
  /// it); "root" administers the global account.
  FileFixture fileFixture(long quota = 0) {
    FileFixture f;
    f.landscape = new FakeLandscape;
    f.landscape.data.global.admins = ["root"];
    Subaccount main, blog;
    main.key = "main";
    main.name = "Main";
    main.members = ["bob"];
    blog.key = "blog";
    blog.name = "Blog";
    blog.admins = ["ann"];
    f.landscape.data.subaccounts = [main, blog];
    f.fileRepo = new FakeFiles;
    f.blobs = new FakeBlobs;
    auto clock = new FixedClock(SysTime(DateTime(2026, 11, 20, 8, 0, 0), UTC()));
    f.files = new ManageFilesUseCase(f.fileRepo, f.landscape, f.blobs, new NoEvents, clock, new SequentialIds("f"),
      FileLimits(100, quota));
    return f;
  }

  UploadFileRequest upload(string subaccount, string name, string content, bool isPublic = false) {
    UploadFileRequest r;
    r.subaccount = subaccount;
    r.name = name;
    r.data = cast(immutable(ubyte)[]) content;
    r.isPublic = isPublic;
    return r;
  }
}

/// Files: upload limits, subaccount scope, public delivery, assigned service.
unittest {
  auto f = fileFixture(60);

  auto logo = f.files.upload(upload("Main", "../Logo.PNG", "png-bytes", true), "admin");
  assert(logo.name == "Logo.PNG" && logo.kind == "image" && logo.inline && logo.size == 9 && logo.isPublic);
  assert(logo.subaccount == "main" && logo.publicUrl == "/media/main/f-1/Logo.PNG");
  auto doc = f.files.upload(upload("main", "Price list.pdf", "pdf"), "admin");
  assert(f.files.list("main", "admin").length == 2);
  assert(fails!ValidationException(() { f.files.upload(upload("main", "big.bin", "x".replicate(101)), "admin"); }));
  assert(fails!ValidationException(() { f.files.upload(upload("main", "empty.txt", ""), "admin"); }));
  assert(fails!PolicyViolationException(() {
      f.files.upload(upload("main", "more.txt", "x".replicate(99)), "admin");
    }));
  assert(fails!NotFoundException(() { f.files.upload(upload("nope", "a.txt", "a"), "admin"); }));
  assert(f.blobs.data.length == 2 && ("main/" ~ logo.id) in f.blobs.data); // refused uploads leave nothing behind

  // public delivery only for public files of the right subaccount
  FileContent c;
  assert(f.files.tryOpenPublic("main", logo.id, c) && cast(string) c.data == "png-bytes");
  assert(!f.files.tryOpenPublic("main", doc.id, c) && !f.files.tryOpenPublic("blog", logo.id, c));
  UpdateFileRequest pub;
  pub.isPublic = nullable(true);
  pub.name = nullable("Prices 2026.pdf");
  auto changed = f.files.update(doc.id, pub, "admin");
  assert(changed.name == "Prices 2026.pdf" && f.files.tryOpenPublic("main", doc.id, c));

  // subaccount scope: members and administrators see their own libraries only
  assert(f.files.list("main", "bob").length == 2 && f.files.list("main", "root").length == 2);
  assert(fails!NotFoundException(() { f.files.list("main", "ann"); }));
  assert(fails!NotFoundException(() { f.files.get(logo.id, "ann"); }));
  assert(fails!NotFoundException(() { f.files.remove(logo.id, "ann"); }));
  f.files.upload(upload("blog", "post.md", "# Hi"), "ann");
  assert(f.files.libraries("ann").map!(x => x.subaccount).array == ["blog"]);
  assert(f.files.libraries("root").length == 2 && f.files.libraries("operator").length == 2);
  auto usage = f.files.storage();
  assert(usage.files == 3 && usage.subaccounts.length == 2 && usage.subaccounts[0].bytes == 12);

  // uploads need the service "files"
  f.landscape.data.subaccounts[1].services = ["landscape"];
  assert(fails!PolicyViolationException(() { f.files.upload(upload("blog", "x.txt", "x"), "ann"); }));
  assert(f.files.list("blog", "ann").length == 1); // existing files stay reachable

  // files of a removed subaccount are listed apart
  f.landscape.data.subaccounts = f.landscape.data.subaccounts[0 .. 1];
  usage = f.files.storage();
  assert(usage.subaccounts.length == 2 && usage.subaccounts[1].name == "blog (removed)");

  f.files.remove(logo.id, "admin");
  assert(f.blobs.get("main", logo.id) is null && f.files.list("main", "admin").length == 1);
}

version (unittest) import std.array : replicate;
