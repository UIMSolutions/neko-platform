/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.infrastructure.persistence.repositories.notification_channels;
// import neko.logging.domain.entities.notification_channel;
// import neko.logging.domain.ports.repositories.notification_channels;

import neko.logging;

mixin(ShowModule!());

@safe:

class NotificationChannelRepository : TenantRepository!(NotificationChannel, NotificationChannelId), INotificationChannelRepository {

  size_t countActive(TenantId tenantId) {
    return findActive(tenantId).length;
  }

  NotificationChannel[] findActive(TenantId tenantId) {
    return findByTenant(tenantId).filter!(ch => ch.state == ChannelState.active).array;
  }

  void removeActive(TenantId tenantId) {
    findActive(tenantId).each!(ch => remove(ch));
  }

}
