/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Fachliche Ausnahmen. Die Adapter bilden sie auf HTTP-Status ab (404, 409, 429).
module neko.database.domain.exceptions;

@safe:

/// Das angefragte Objekt gibt es nicht (HTTP 404).
class NotFound : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Das Objekt gibt es schon, oder der Zustand erlaubt die Aktion nicht (HTTP 409).
class Conflict : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

/// Eine Grenze der Workload-Klasse wurde überschritten (HTTP 429).
class WorkloadLimitExceeded : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}
