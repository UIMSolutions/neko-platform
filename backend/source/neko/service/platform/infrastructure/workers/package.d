/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Background workers (vibe.d timers in the event loop).
module neko.platform.infrastructure.workers;

import core.time : seconds;
import vibe.core.core : setTimer, Timer;
import vibe.core.log : logInfo, logWarn;
import neko.platform.ports.usecases;

@safe:

/// Periodically probes the health of all active services.
class HealthCheckWorker {
  private ICheckServiceHealthUseCase usecase;
  private int intervalSeconds;
  private Timer timer;

  this(ICheckServiceHealthUseCase usecase, int intervalSeconds) {
    this.usecase = usecase;
    this.intervalSeconds = intervalSeconds;
  }

  bool enabled() const {
    return intervalSeconds > 0;
  }

  void start() {
    if (!enabled)
      return;
    timer = setTimer(intervalSeconds.seconds, &tick, true);
    logInfo("health worker: probing active services every %d s", intervalSeconds);
  }

  void stop() {
    if (timer)
      timer.stop();
  }

  private void tick() nothrow {
    try
      usecase.checkAll();
    catch (Exception e)
      logWarn("health worker: %s", e.msg);
  }
}
