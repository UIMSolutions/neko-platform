/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*) 
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file. 
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.logging.domain.ports.repositories.notification_channels;
// import neko.logging.domain.entities.notification_channel;

import neko.logging;

mixin(ShowModule!());

@safe:
interface INotificationChannelRepository : ITenantRepository!(NotificationChannel, NotificationChannelId) {

  size_t countActive(TenantId tenantId);
  NotificationChannel[] findActive(TenantId tenantId);
  void removeActive(TenantId tenantId);

}
