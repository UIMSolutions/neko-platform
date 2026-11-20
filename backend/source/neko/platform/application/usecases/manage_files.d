/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// The file library of the sites: metadata in a repository, content in a
/// blob store (one folder per site).
module neko.platform.application.usecases.manage_files;

import std.algorithm : filter, map, sort;
import std.array : array;
import std.string : strip;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.application.usecases.access;
import neko.platform.application.usecases.manage_sites : countText;
import neko.platform.ports;

@safe:

/// Upload limits (configuration).
struct FileLimits {
  /// Per file.
  long maxFileBytes = 50 * 1024 * 1024;
  /// Per site; 0 = no quota.
  long siteQuotaBytes = 0;
}

class ManageFilesUseCase : IManageFilesUseCase {
  private IFileRepository files;
  private ISiteRepository sites;
  private IBlobStore blobs;
  private IUserRepository users;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  private FileLimits limits;

  this(IFileRepository files, ISiteRepository sites, IBlobStore blobs, IUserRepository users, IEventPublisher events,
      IClock clock, IIdGenerator ids, FileLimits limits = FileLimits.init) {
    this.files = files;
    this.sites = sites;
    this.blobs = blobs;
    this.users = users;
    this.events = events;
    this.clock = clock;
    this.ids = ids;
    this.limits = limits;
  }

  FileDto[] list(string site, string actor) {
    auto key = requireExistingSite(site, actor);
    auto list = files.ofSite(key);
    list.sort!((a, b) => a.createdAt > b.createdAt || (a.createdAt == b.createdAt && a.name < b.name));
    return list.map!(f => f.toDto).array;
  }

  FileDto get(string id, string actor) {
    return load(id, actor).toDto;
  }

  FileDto upload(UploadFileRequest request, string actor) {
    auto key = requireExistingSite(request.site, actor);
    auto now = clock.now;
    StoredFile file;
    file.id = FileId(ids.newId);
    file.site = SiteKey(key);
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
    if (limits.siteQuotaBytes > 0) {
      long used;
      foreach (f; files.ofSite(key))
        used += f.size;
      if (used + info.size > limits.siteQuotaBytes)
        throw new PolicyViolationException("The site " ~ key ~ " would exceed its quota of "
            ~ byteSize(limits.siteQuotaBytes) ~ " (" ~ byteSize(used) ~ " used)");
    }
    file.size = info.size;
    file.sha256 = info.sha256;
    files.save(file);
    emit("file.uploaded", file.id.value, actor, "Uploaded " ~ file.name ~ " (" ~ byteSize(file.size) ~ ") to site "
        ~ key ~ (file.isPublic ? ", public" : ""));
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
      (published ? (file.isPublic ? "Published " : "Withdrew ") : "Changed ") ~ file.name ~ " of site "
        ~ file.site.value);
    return file.toDto;
  }

  void remove(string id, string actor) {
    auto file = load(id, actor);
    files.remove(file.id);
    blobs.remove(file.site.value, file.id.value);
    emit("file.removed", file.id.value, actor, "Removed " ~ file.name ~ " from site " ~ file.site.value);
  }

  FileContent open(string id, string actor) {
    return content(load(id, actor));
  }

  bool tryOpenPublic(string site, string id, out FileContent result) {
    StoredFile file;
    if (!files.tryGet(FileId(id.strip), file) || !file.isPublic || file.site.value != site)
      return false;
    Site s;
    if (!sites.tryGet(site, s))
      return false;
    result = content(file);
    return true;
  }

  StorageDto storage() {
    StorageDto d;
    auto all = files.all;
    auto list = sites.all;
    list.sort!((a, b) => a.key.value < b.key.value);
    foreach (s; list) {
      SiteUsageDto u = SiteUsageDto(s.key.value, s.name);
      foreach (f; all)
        if (f.site == s.key) {
          u.files++;
          u.bytes += f.size;
        }
      d.files += u.files;
      d.bytes += u.bytes;
      d.sites ~= u;
    }
    d.available = blobs.available;
    d.location = blobs.describe;
    return d;
  }

  private FileContent content(const StoredFile file) {
    FileContent c;
    c.file = file.toDto;
    c.localPath = blobs.localPath(file.site.value, file.id.value);
    if (c.localPath.length == 0)
      c.data = blobs.get(file.site.value, file.id.value).idup;
    return c;
  }

  private string requireExistingSite(string site, string actor) {
    auto key = SiteKey(site).value;
    Site s;
    if (!sites.tryGet(key, s))
      throw new NotFoundException("Site", site);
    requireSite(users, actor, key);
    return key;
  }

  private StoredFile load(string id, string actor) {
    StoredFile file;
    if (!files.tryGet(FileId(id.strip), file) || !mayAccessSite(users, actor, file.site.value))
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
  import neko.platform.application.usecases.manage_sites : ManageSitesUseCase;
  import neko.platform.application.usecases.manage_users : FakeUsers, fails, NoEvents;
  import std.datetime.date : DateTime;
  import std.datetime.systime : SysTime;
  import std.datetime.timezone : UTC;

  class FakeSites : ISiteRepository {
    Site[string] items;

    Site[] all() {
      return items.values;
    }

    bool tryGet(string key, out Site s) {
      if (auto p = key in items) {
        s = *p;
        return true;
      }
      return false;
    }

    void save(Site s) {
      items[s.key.value] = s;
    }

    bool remove(string key) {
      return items.remove(key);
    }
  }

  class FakeFiles : IFileRepository {
    StoredFile[string] items;

    StoredFile[] all() {
      return items.values;
    }

    StoredFile[] ofSite(string site) {
      StoredFile[] r;
      foreach (f; items)
        if (f.site.value == site)
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

  struct SiteFixture {
    FakeUsers users;
    FakeSites siteRepo;
    FakeFiles fileRepo;
    FakeBlobs blobs;
    ManageSitesUseCase sites;
    ManageFilesUseCase files;
  }

  SiteFixture siteFixture(long quota = 0) {
    SiteFixture f;
    f.users = new FakeUsers;
    f.siteRepo = new FakeSites;
    f.fileRepo = new FakeFiles;
    f.blobs = new FakeBlobs;
    auto clock = new FixedClock(SysTime(DateTime(2026, 11, 20, 8, 0, 0), UTC()));
    auto events = new NoEvents;
    f.sites = new ManageSitesUseCase(f.siteRepo, f.fileRepo, f.users, events, clock);
    f.files = new ManageFilesUseCase(f.fileRepo, f.siteRepo, f.blobs, f.users, events, clock, new SequentialIds("f"),
      FileLimits(100, quota));
    return f;
  }

  void addAccount(FakeUsers users, string name, string[] sites) {
    UserAccount a;
    a.id = AccountId(name);
    a.userName = UserName(name);
    a.roles = [adminRole];
    a.sites = sites;
    users.save(a);
  }

  UploadFileRequest upload(string site, string name, string content, bool isPublic = false) {
    UploadFileRequest r;
    r.site = site;
    r.name = name;
    r.data = cast(immutable(ubyte)[]) content;
    r.isPublic = isPublic;
    return r;
  }
}

/// Sites: default site, host names, languages, public page.
unittest {
  auto f = siteFixture();
  assert(f.sites.ensureDefaultSite("Neko", "de") == "main");
  assert(f.sites.ensureDefaultSite("Other", "en") == "main"); // only once
  auto main = f.sites.get("main", "system");
  assert(main.isDefault && main.languages == ["de"] && main.contentFor("de").title == "Neko");

  CreateSiteRequest shop;
  shop.key = "Shop";
  shop.name = "Shop";
  shop.hosts = ["shop.example.org:8080"];
  shop.defaultLanguage = "en";
  shop.languages = ["de-CH", "fr"];
  auto s = f.sites.create(shop, "admin");
  assert(s.key == "shop" && !s.isDefault && s.languages == ["en", "de-CH", "fr"] && s.hosts == ["shop.example.org"]);
  assert(fails!ConflictException(() { f.sites.create(shop, "admin"); }));
  CreateSiteRequest clash;
  clash.key = "other";
  clash.hosts = ["SHOP.example.org"];
  assert(fails!ConflictException(() { f.sites.create(clash, "admin"); }));

  f.sites.updateContent("shop", UpdateSiteContentRequest("de-ch", "Willkommen", "", "Eins\n\nZwei"), "admin");
  f.sites.updateContent("shop", UpdateSiteContentRequest("en", "Welcome"), "admin");
  assert(fails!ValidationException(() {
      f.sites.updateContent("shop", UpdateSiteContentRequest("it", "Benvenuti"), "admin");
    }));

  // the public page: by host name, else the default site; language by ?lang=, Accept-Language, default
  auto p = f.sites.page("shop.example.org:8080", "", "de-DE,de;q=0.9");
  assert(p.site.key == "shop" && p.language == "de-CH" && p.content.paragraphs == ["Eins", "Zwei"]);
  assert(f.sites.page("SHOP.example.org", "fr", "de").language == "fr");
  assert(f.sites.page("shop.example.org", "fr", "").content.title == "Welcome"); // no French text yet
  assert(f.sites.page("unknown.example.org", "", "").site.key == "main");

  // default site
  assert(fails!InvalidStateTransitionException(() { f.sites.remove("main", "admin"); }));
  f.sites.makeDefault("shop", "admin");
  assert(f.sites.page("localhost", "", "").site.key == "shop");
  assert(f.sites.list("admin")[0].key == "shop" && !f.sites.get("main", "admin").isDefault);

  UpdateSiteRequest langs;
  langs.defaultLanguage = nullable("fr");
  assert(fails!ValidationException(() { f.sites.update("shop", langs, "admin"); })); // both or neither
  langs.languages = nullable(["en"]);
  assert(f.sites.update("shop", langs, "admin").languages == ["fr", "en"]);
  assert(f.sites.get("shop", "admin").content.length == 1); // de-CH text kept, but not shown

  // tenants: an account limited to sites sees only those
  addAccount(f.users, "sam", ["shop"]);
  assert(f.sites.list("sam").length == 1);
  assert(fails!NotFoundException(() { f.sites.get("main", "sam"); }));
  assert(fails!PolicyViolationException(() { f.sites.create(clash, "sam"); }));
  assert(fails!PolicyViolationException(() { f.sites.makeDefault("shop", "sam"); }));
  f.sites.updateContent("shop", UpdateSiteContentRequest("en", "Hello"), "sam");

  // removal: not while an account works on it
  f.sites.makeDefault("main", "admin");
  assert(fails!ConflictException(() { f.sites.remove("shop", "admin"); }));
  f.users.items.remove("sam");
  f.sites.remove("shop", "admin");
  assert(f.sites.list("admin").length == 1);
}

/// Files: upload limits, tenants, public delivery.
unittest {
  auto f = siteFixture(60);
  f.sites.ensureDefaultSite("Neko", "en");
  CreateSiteRequest blog;
  blog.key = "blog";
  f.sites.create(blog, "admin");

  auto logo = f.files.upload(upload("main", "../Logo.PNG", "png-bytes", true), "admin");
  assert(logo.name == "Logo.PNG" && logo.kind == "image" && logo.inline && logo.size == 9 && logo.isPublic);
  assert(logo.publicUrl == "/media/main/f-1/Logo.PNG");
  auto doc = f.files.upload(upload("main", "Price list.pdf", "pdf"), "admin");
  assert(f.files.list("main", "admin").length == 2);
  assert(fails!ValidationException(() { f.files.upload(upload("main", "big.bin", "x".replicate(101)), "admin"); }));
  assert(fails!ValidationException(() { f.files.upload(upload("main", "empty.txt", ""), "admin"); }));
  assert(fails!PolicyViolationException(() { f.files.upload(upload("main", "more.txt", "x".replicate(99)), "admin"); }));
  assert(fails!NotFoundException(() { f.files.upload(upload("nope", "a.txt", "a"), "admin"); }));
  assert(f.blobs.data.length == 2); // refused uploads leave nothing behind

  // public delivery only for public files of the right site
  FileContent c;
  assert(f.files.tryOpenPublic("main", logo.id, c) && cast(string) c.data == "png-bytes");
  assert(!f.files.tryOpenPublic("main", doc.id, c) && !f.files.tryOpenPublic("blog", logo.id, c));
  UpdateFileRequest pub;
  pub.isPublic = nullable(true);
  pub.name = nullable("Prices 2026.pdf");
  auto changed = f.files.update(doc.id, pub, "admin");
  assert(changed.name == "Prices 2026.pdf" && f.files.tryOpenPublic("main", doc.id, c));
  auto page = f.sites.page("", "", "");
  assert(page.images.length == 1 && page.documents.length == 1 && page.site.files == 2 && page.site.bytes == 12);

  // tenants
  addAccount(f.users, "bea", ["blog"]);
  assert(fails!NotFoundException(() { f.files.list("main", "bea"); }));
  assert(fails!NotFoundException(() { f.files.get(logo.id, "bea"); }));
  assert(fails!NotFoundException(() { f.files.remove(logo.id, "bea"); }));
  f.files.upload(upload("blog", "post.md", "# Hi"), "bea");
  auto usage = f.files.storage();
  assert(usage.files == 3 && usage.sites.length == 2);

  // a site with files cannot be removed
  assert(fails!ConflictException(() { f.sites.remove("blog", "admin"); }));
  f.files.remove(logo.id, "admin");
  assert(f.blobs.get("main", logo.id) is null && f.files.list("main", "admin").length == 1);
}

version (unittest) import std.array : replicate;
