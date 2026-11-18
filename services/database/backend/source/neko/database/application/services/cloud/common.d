/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Gemeinsames der Cloud-Dienste: Zeit, Rechteprüfung und Audit.
module neko.database.application.services.cloud.common;

import neko.database.domain;
import neko.database.ports.ports : AuditRecord, IAuditTrail;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;

@safe:

/// Jetzt in UTC auf ganze Sekunden, ISO-Format.
string utcNow() {
    auto t = Clock.currTime(UTC());
    t.fracSecs = typeof(t.fracSecs).zero;
    return t.toISOExtString;
}

/// Angemeldet und Mitglied eines Mandanten (nicht system).
void requireTenantUser(Principal actor) {
    if (!actor.authenticated)
        throw new AuthenticationRequired;
    if (actor.isSystem)
        throw new AccessDenied("System administrators have no access to tenant objects");
}

/// Recht im Mandanten.
void requireTenantPermission(Principal actor, Permission p) {
    requireTenantUser(actor);
    requirePermission(actor, p);
}

/// Eines der Rechte im Mandanten.
void requireAnyTenantPermission(Principal actor, Permission[] ps...) {
    requireTenantUser(actor);
    foreach (p; ps)
        if (actor.can(p))
            return;
    throw new AccessDenied("Requires permission " ~ permissionName(ps[0]));
}

/// Recht im Bereich system.
void requireSystemPermission(Principal actor, Permission p) {
    if (!actor.authenticated)
        throw new AuthenticationRequired;
    if (!actor.isSystem)
        throw new AccessDenied("Only system administrators manage instances");
    requirePermission(actor, p);
}

/// Zeichnet eine Aktion im Audit-Protokoll auf, mit Erfolg oder Fehlermeldung. `trail` null: ohne Audit.
struct CloudAudit {
    IAuditTrail trail;
    string delegate() @safe address;

    T run(T)(Principal actor, string category, string action, string target, string detail,
        scope T delegate() @safe body_) {
        auto r = AuditRecord(actor.tenant, actor.name, address is null ? "" : address(), category, action, target,
            true, detail);
        try {
            static if (is(T == void)) {
                body_();
                if (trail !is null)
                    trail.audit(r);
            } else {
                auto result = body_();
                if (trail !is null)
                    trail.audit(r);
                return result;
            }
        } catch (Exception e) {
            r.success = false;
            r.message = e.msg;
            if (trail !is null)
                trail.audit(r);
            throw e;
        }
    }
}
