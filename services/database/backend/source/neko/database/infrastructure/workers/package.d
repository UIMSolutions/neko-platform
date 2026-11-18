/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Hintergrundaufgaben: wiederkehrende Arbeiten auf vibe.d-Timern. Ein Lauf überlappt sich nie mit sich selbst,
/// Fehler landen im Log und beenden den Takt nicht.
module neko.database.infrastructure.workers;

import core.time : Duration;
import vibe.core.core : setTimer, Timer;
import vibe.core.log : logWarn;

@safe:

/// Eine benannte, periodische Aufgabe. `run` liefert Fehlermeldungen; leere Einträge werden ignoriert.
struct PeriodicJob {
    string name;
    Duration interval;
    string[] delegate() @safe run;
    bool immediately; // einmal direkt beim Start
}

/// Startet und hält alle periodischen Aufgaben.
final class Workers {
    private Timer[] timers;
    private bool[string] running;

    void schedule(PeriodicJob job) {
        auto name = job.name;
        auto run = job.run;
        void tick() nothrow @safe {
            try {
                if (running.get(name, false))
                    return;
                running[name] = true;
                scope (exit)
                    running[name] = false;
                foreach (error; run())
                    if (error.length)
                        logWarn("%s fehlgeschlagen: %s", name, error);
            } catch (Exception e) {
                try
                    logWarn("%s fehlgeschlagen: %s", name, e.msg);
                catch (Exception) {
                }
            }
        }

        if (job.immediately)
            tick();
        timers ~= setTimer(job.interval, &tick, true);
    }

    void stop() {
        foreach (ref t; timers)
            t.stop();
        timers = null;
    }

    size_t count() const {
        return timers.length;
    }
}
