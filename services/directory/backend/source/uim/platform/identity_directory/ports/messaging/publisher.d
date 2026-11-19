/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
module neko.directory.ports.messaging.publisher;

import neko.directory;

mixin(ShowModule!());

@safe:

/// Driven port: publishes domain events ("identity.user.created", ...) to an
/// event broker (SAP Event Mesh, Kafka) or the technical log.
interface IDirectoryEventPublisher {
  void publish(string topic, Json payload);
}
