/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// One-way, integrity-protected transfers between security domains.
module neko.service.platform.application.usecases.transfer_packages;

import std.algorithm : map, sort;
import std.array : array;
import std.conv : to;
import std.string : strip;
import neko.service.platform.domain;
import neko.service.platform.application.dtos;
import neko.service.platform.ports;

@safe:

class TransferPackagesUseCase : ITransferPackagesUseCase {
  private ITransferRepository transfers;
  private IEventPublisher events;
  private IClock clock;
  private IIdGenerator ids;
  private TransferPolicy policy;
  private size_t maxPayloadBytes;

  this(ITransferRepository transfers, IEventPublisher events, IClock clock, IIdGenerator ids,
      SecurityDomain platformDomain, size_t maxPayloadBytes = 10 * 1024 * 1024) {
    this.transfers = transfers;
    this.events = events;
    this.clock = clock;
    this.ids = ids;
    this.policy = TransferPolicy(platformDomain);
    this.maxPayloadBytes = maxPayloadBytes;
  }

  TransferDto[] list() {
    auto items = transfers.all;
    items.sort!((a, b) => a.createdAt > b.createdAt); // newest first
    return items.map!(t => t.toDto).array;
  }

  TransferDto get(string id) {
    return load(id).toDto;
  }

  TransferDto exportPackage(ExportPackageRequest request, string actor) {
    SecurityDomain target;
    if (!tryParseSecurityDomain(request.targetDomain, target))
      throw new ValidationException("Unknown target domain '" ~ request.targetDomain ~ "'");
    policy.requireExportTo(target);

    auto name = request.name.strip;
    if (name.length == 0)
      throw new ValidationException("A transfer package needs a name");
    if (request.payload.length == 0)
      throw new ValidationException("A transfer package needs a payload");
    requireSize(request.payload.length);

    TransferPackage pkg;
    pkg.id = TransferId(ids.newId);
    pkg.name = name;
    pkg.direction = TransferDirection.outbound;
    pkg.sourceDomain = policy.platformDomain;
    pkg.targetDomain = target;
    pkg.status = TransferStatus.exported;
    pkg.payload = request.payload;
    pkg.createdBy = actor;
    pkg.createdAt = clock.now;
    pkg.checksum = TransferPolicy.seal(pkg);

    transfers.save(pkg);
    emit("transfer.exported", pkg, actor, "Exported '" ~ name ~ "' to " ~ target.label);
    return pkg.toDto;
  }

  TransferDto importPackage(ImportPackageRequest request, string actor) {
    auto pkg = fromDocument(request.document);
    requireSize(pkg.payload.length);

    TransferPackage existing;
    if (transfers.tryGet(pkg.id, existing) && existing.status != TransferStatus.rejected)
      throw new ConflictException("Transfer '" ~ pkg.id.value ~ "' was already " ~ existing.status.to!string);

    try {
      policy.requireImportable(pkg);
    } catch (PlatformException e) {
      // Keep an audit record of every refused package, then report the refusal.
      pkg.status = TransferStatus.rejected;
      pkg.reason = e.msg;
      pkg.createdAt = clock.now;
      transfers.save(pkg);
      emit("transfer.rejected", pkg, actor, e.msg);
      throw e;
    }

    pkg.status = TransferStatus.imported;
    if (pkg.createdAt == typeof(pkg.createdAt).init)
      pkg.createdAt = clock.now;
    transfers.save(pkg);
    emit("transfer.imported", pkg, actor, "Imported '" ~ pkg.name ~ "' from " ~ pkg.sourceDomain.label);
    return pkg.toDto;
  }

  string document(string id) {
    auto pkg = load(id);
    if (pkg.direction != TransferDirection.outbound)
      throw new ValidationException("Only outbound packages can be downloaded");
    return toDocument(pkg).toPrettyString;
  }

  private TransferPackage load(string id) {
    TransferPackage pkg;
    if (!transfers.tryGet(TransferId(id), pkg))
      throw new NotFoundException("Transfer", id);
    return pkg;
  }

  private void requireSize(size_t bytes) const {
    if (bytes > maxPayloadBytes)
      throw new ValidationException("Payload exceeds " ~ maxPayloadBytes.to!string ~ " bytes");
  }

  private void emit(string type, const TransferPackage pkg, string actor, string message) {
    events.publish(PlatformEvent(type, pkg.id.value, actor, message, clock.now));
  }
}

version (unittest) {
  class FakeTransfers : ITransferRepository {
    TransferPackage[string] items;

    TransferPackage[] all() {
      return items.values;
    }

    bool tryGet(TransferId id, out TransferPackage t) {
      if (auto p = id.value in items) {
        t = *p;
        return true;
      }
      return false;
    }

    void save(TransferPackage t) {
      items[t.id.value] = t;
    }
  }
}

///
unittest {
  import std.datetime.systime : SysTime;
  import std.string : replace;
  import neko.service.platform.application.services : FixedClock, SequentialIds;
  import neko.service.platform.application.usecases.manage_services : RecordingEvents;

  auto clock = new FixedClock(SysTime(0));
  auto openSide = new TransferPackagesUseCase(new FakeTransfers, new RecordingEvents, clock,
    new SequentialIds("tx"), SecurityDomain.open);
  auto secretRepo = new FakeTransfers;
  auto secretSide = new TransferPackagesUseCase(secretRepo, new RecordingEvents, clock,
    new SequentialIds("unused"), SecurityDomain.secret);

  auto exported = openSide.exportPackage(ExportPackageRequest("feed", "secret", `{"x":1}`), "ops");
  assert(exported.status == "exported" && exported.direction == "outbound");
  auto doc = openSide.document(exported.id);

  auto imported = secretSide.importPackage(ImportPackageRequest(doc), "ops");
  assert(imported.status == "imported" && imported.sourceDomain == "open");

  // replay protection
  bool replay;
  try
    secretSide.importPackage(ImportPackageRequest(doc), "ops");
  catch (ConflictException)
    replay = true;
  assert(replay);

  // tampering is rejected and recorded
  auto other = openSide.exportPackage(ExportPackageRequest("feed2", "secret", "abc"), "ops");
  auto tampered = openSide.document(other.id).replace(`"abc"`, `"abd"`);
  bool integrity;
  try
    secretSide.importPackage(ImportPackageRequest(tampered), "ops");
  catch (IntegrityException)
    integrity = true;
  assert(integrity);
  assert(secretRepo.items[other.id].status == TransferStatus.rejected);

  // secret cannot export at all
  bool noExport;
  try
    secretSide.exportPackage(ExportPackageRequest("leak", "open", "x"), "ops");
  catch (PolicyViolationException)
    noExport = true;
  assert(noExport);
}
