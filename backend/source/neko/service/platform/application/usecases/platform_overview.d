/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Key figures of this platform instance (cockpit header, status page).
module neko.platform.application.usecases.platform_overview;

import std.algorithm : map;
import std.array : array;
import neko.platform.domain;
import neko.platform.application.dtos;
import neko.platform.ports;

@safe:

class PlatformOverviewUseCase : IPlatformOverviewUseCase {
  private IServiceRepository services;
  private ITransferRepository transfers;
  private SecurityDomain domain;
  private string environment;

  this(IServiceRepository services, ITransferRepository transfers, SecurityDomain domain, string environment) {
    this.services = services;
    this.transfers = transfers;
    this.domain = domain;
    this.environment = environment;
  }

  OverviewDto overview() {
    OverviewDto o;
    o.domain = domain.label;
    o.canExport = domain.canExport;
    o.canImport = domain.canImport;
    o.exportTargets = domain.higherDomains.map!(d => d.label).array;
    o.environment = environment;

    foreach (s; services.all) {
      o.serviceCount++;
      if (s.status == ServiceStatus.active)
        o.activeServices++;
      if (s.status == ServiceStatus.active && s.health == HealthState.down)
        o.servicesDown++;
    }
    foreach (t; transfers.all) {
      o.transferCount++;
      if (t.status == TransferStatus.rejected)
        o.rejectedTransfers++;
      else if (t.direction == TransferDirection.outbound)
        o.outboundTransfers++;
      else
        o.inboundTransfers++;
    }
    return o;
  }
}
