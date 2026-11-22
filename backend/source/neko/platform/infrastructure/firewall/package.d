/****************************************************************************************************************
* Copyright: © 2018-2026 Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
* License: Subject to the terms of the Apache 2.0 license, as written in the included LICENSE.txt file.
* Authors: Ozan Nurettin Süel (aka UI-Manufaktur UG *R.I.P*)
*****************************************************************************************************************/
/// Web application firewall: request inspection rules, a per-client rate
/// limit and automatic bans. Framework-free, so the rules are unit-tested
/// here; presentation.http.firewall applies them to vibe.d requests.
///
/// Inspection looks at the method, the request URI (raw and decoded), the
/// User-Agent, and the values of query parameters and URL-encoded form
/// fields (not uploads). Fields that legitimately hold anything — passwords —
/// are skipped (`skipFields`).
module neko.platform.infrastructure.firewall;

public:
  import neko.platform.infrastructure.firewall.ban;
  import neko.platform.infrastructure.firewall.banlist;
  import neko.platform.infrastructure.firewall.helpers;
  import neko.platform.infrastructure.firewall.mode;
  import neko.platform.infrastructure.firewall.ratelimiter;
  import neko.platform.infrastructure.firewall.tests;
  import neko.platform.infrastructure.firewall.waffinding;
  import neko.platform.infrastructure.firewall.wafinspector;
  import neko.platform.infrastructure.firewall.wafrequest;