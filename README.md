# Neko Platform

A service platform for organisations that separate their IT into **security
domains** — `open` → `restricted` → `confidential` → `secret`. Every domain runs
its own platform instance. Each instance:

- keeps a **catalogue of the services** it hosts (register, activate, suspend,
  retire, health monitoring), and
- moves data to other domains only as **sealed transfer packages**, and only
  **upwards** (no write-down). Packages are protected by SHA-256, replays and
  tampering are refused, and every refusal is kept as an audit record.

The domain is compiled into the binary (`dub --config=<domain>`), so a binary
built for `secret` can never run as `open`.

```text
backend/      D 2.x + vibe.d — hexagonal architecture (REST, OData v4, CLI, web, unix socket)
frontend/     SAP Fiori 3 cockpit (OpenUI5, OData v4 model)
approuter/    SAP approuter: XSUAA login, routing, CSRF (Cloud Foundry)
mta.yaml      deploys backend + approuter + XSUAA to SAP BTP
services/     services hosted on the platform (management)
```

Further reading: [naf.md](naf.md) (NAF v4 views) · [uml.md](uml.md) (class and
component diagrams) · [backend/docs/api.md](backend/docs/api.md) (API reference).

## Quick start

Requirements: `dmd` or `ldc2`, `dub`; for the UI additionally Node.js ≥ 20.

```bash
dub build --config=open            # → backend/build/platform-open
./backend/build/platform-open      # http://127.0.0.1:8080
```

| URL | What |
| --- | --- |
| `/` | the public site: the site claiming the request's host name, otherwise the default site (no sign-in) |
| `/media/<site>/<id>/<name>` | public files of a site |
| `/login` | sign-in for the server-rendered pages |
| `/status` | status page (vibe.d web interface, Tabler + htmx, all assets embedded — works in isolated domains) |
| `/monitoring` | request figures, failures, slow requests, recent log, storage |
| `/security` | firewall events, network traffic per client, IP allow/deny lists, bans |
| `/landscape` | account hierarchy: global account → directories → subaccounts, entitlements, role collections, recommendations |
| `/landscape/billing` | usage and costs per subaccount, directory and global account; CSV export |
| `/sites` | sites (tenants): host names, languages, home page content per language |
| `/files` | file library per site: documents, images, audio, video |
| `/users`, `/roles` | user management, roles and the access rights they grant |
| `/account` | own roles and rights, password change |
| `/index.html` | Fiori cockpit (needs a frontend build, see below) |
| `/rest/v1/…` | REST API |
| `/odata/v4/platform/$metadata` | OData v4 service for Fiori |
| `/health`, `/api/v1/info` | liveness, effective configuration |
| `/metrics` | Prometheus metrics (local scrapers, or `Authorization: Bearer <metricsToken>`) |

**Sign-in.** Each domain has its own web user accounts (stored with its data).
On the first start without accounts the server creates the administrator
`adminUser` (default `admin`) with `adminPassword` / `NEKO_ADMIN_PASSWORD`; if
none is set, it generates a password and prints it once in the log. Locked out?
Use the CLI on the same data directory:

```bash
./build/platform-open users list
echo 'a-new-password' | ./build/platform-open users passwd admin
./build/platform-open users add --name=ops --roles=admin   # password from stdin
```

**Roles and access rights.** What a web user may do follows from fixed access
rights: `status.read`, `events.read`, `monitoring.read`, `sites.read`,
`sites.manage`, `files.read`, `files.manage`, `security.read`,
`security.manage`, `landscape.read`, `landscape.manage`, `billing.read`,
`users.read`, `users.manage`,
`roles.read`, `roles.manage`. Roles bundle rights and are managed at runtime
(page `/roles` or `roles …` on the CLI). A user holds one or more roles, and
holds the union of their rights. Every domain starts with four built-in roles:

| Role | Rights |
| --- | --- |
| `admin` | every right, including rights added later; not editable |
| `auditor` | every `….read` right; changes nothing |
| `editor` | `status.read`, `sites.read`, `sites.manage`, `files.read`, `files.manage` |
| `viewer` | `status.read` (the default for new users) |

When a new version adds rights, built-in roles stored by an older version
gain the rights their shipped definition has (once, at start-up); rights an
administrator took away stay away.

Nobody can grant rights they do not hold themselves. That covers assigning a
role to a user and adding a right to a role, and it also blocks changing an
account or role that holds more rights than you do. At least one active
`admin` always remains. Role changes take effect on the next request. Built-in
roles cannot be removed, and neither can a custom role while a user still holds
it. User documents written before roles existed keep working: their `role`
field (`viewer` or `admin`) is read as the built-in role of the same name.

```bash
./build/platform-open roles add --name=ops --label=Operators --rights=status.read,events.read
./build/platform-open users roles jane viewer,ops
./build/platform-open roles rights                         # the catalogue
```

The REST and OData APIs are unchanged: they are still protected by the
approuter / XSUAA scopes (`enforceScopes`), not by web roles.

**Sites (multi-tenancy).** An instance serves several sites. Each site has a
key, a name, host names, languages (the first is the default language), a home
page per language, and its own file library. A request is answered by the site
that claims its host name; all other host names get the **default site** at
`/`. On the first start the instance creates the default site `main` (named
after `serviceName`, language `defaultLanguage`). The language of a page comes
from `?lang=`, else the browser's `Accept-Language`, else the site's default
language; a language without its own text shows the default language's text.
Signed-in users preview any of their sites with `/?site=<key>`.

Accounts can be limited to some sites (user dialog, or `users sites <name> a,b`).
Site rights (`sites.*`, `files.*`) then apply to those sites only, and the
others do not exist for the user. Creating, removing and choosing the default
site needs access to every site, and a limited user can only manage accounts
within their own sites. A site can only be removed once it has no files and no
account is limited to it.

**Files.** Uploads (several at once, up to `maxUploadBytes` each, optionally a
`siteQuotaBytes` per site) are stored on the file system under
`<dataDir>/<domain>/files/<site>/<id>`; the metadata (name, size, SHA-256,
description, public flag) is in `files.json`. The content type follows the file
name's extension and is never taken from the client. Public files appear on the
site's page (images, audio/video players, documents) and under `/media/…`.
Raster images, audio, video and PDF are shown in place; everything else,
including SVG and HTML, is only sent as a download, and every file is sent with
a sandboxing Content-Security-Policy and `nosniff`.

```bash
./build/platform-open sites add --key=shop --name=Shop --hosts=shop.example.org --language=de --languages=en,fr
./build/platform-open sites content shop --lang=de --title="Willkommen" --file=intro-de.txt
./build/platform-open files add shop price-list.pdf logo.png --public
./build/platform-open files usage
```

**Logging and monitoring.** Every request is measured and, with `accessLog`,
logged (assets and probes only at debug level). With file storage, the log is
also written to `<dataDir>/<domain>/logs/platform-YYYY-MM-DD.log` and each
request to `access-YYYY-MM-DD.ndjson` (one JSON object per line, without query
strings); files older than `logRetentionDays` are removed. `/monitoring`
(`monitoring.read`) shows uptime, request rate, errors, latency (average, p95,
histogram), figures per area, the latest failed and slow requests, storage per
site and the recent log with a level filter; it refreshes every 10 seconds.
`/metrics` exposes the same figures in the Prometheus format. Without
`metricsToken` it only answers local clients (and the unix socket).

**Landscape: global account, directories, subaccounts.** `/landscape` models
the account hierarchy of the operator (after SAP BTP):

| Level | Holds |
| --- | --- |
| Global account | governance: contract (CPEA, PAYG, subscription), currency, cost center, contacts; the purchased entitlements; global role collections; the subdomain scheme |
| Directories (nested up to 5 levels) | a group of subaccounts with owner and cost center; optionally **own entitlements** (a budget its subaccounts draw from) and **own role collections** (valid for every subaccount below) |
| Subaccounts | region (`eu10`, `eu11` EU Access, `eu20`, `us10`, …, `onprem`), subdomain, purpose, stage (`sandbox`, `dev`, `test`, `qa`, `prod`), security domain, the sites (tenants) of this instance, entitlements, role collections |

The subdomain follows the scheme of the global account (default
`{global}-{purpose}-{stage}`, also `{directory}` and `{region}`), e.g.
`acme-shop-prod`; it must be unique, and — as region — cannot change once the
subaccount exists. Entitlements flow down: a subaccount draws from the nearest
directory above it that manages entitlements, else from the global account;
quotas may be unlimited (pay per use). Every change is refused if it would
introduce an error: over-assigned quotas, plans the source is not entitled
to, duplicate subdomains, a site in two subaccounts, more sites than the
`sites.site` entitlement, cycles or more than five directory levels.

**Where directory entitlements and role collections make sense.** The page
explains it, and a built-in advisor checks the landscape:

- *Directory entitlements* pay off when a directory groups several
  subaccounts with their own budget owner or cost center (a business unit, a
  customer): the owner distributes the quota without the global account
  administrators. For a single subaccount they only add a level of
  bookkeeping — the advisor recommends turning them off.
- *Directory role collections* pay off when the same people administer every
  subaccount below in the same way (the advisor spots identical role
  collections on all subaccounts). They do **not** belong on a directory that
  mixes production and non-production subaccounts when they grant changing
  rights: the advisor recommends moving them to the subaccounts or splitting
  the directory (segregation of duties).
- Further advice: one directory per security domain, no beta features in
  production, EU Access or self-hosted regions for confidential/secret
  subaccounts, small global role collections, few production administrators.

Role collections here describe the authorizations of the landscape
(governance); the platform's own pages are still protected by the roles under
`/roles`.

**Billing.** The platform measures, per site and month, the requests and
bytes of its public pages (`/` by host name, `/media/…`) and the peak size of
its files, and stores them every minute (`usage.json`). A site belongs to one
subaccount, so usage adds up per subaccount, directory and global account.
Service plans (`/landscape/billing`, editable) price it: measured plans cost
quantity × price, plans without a meter cost their entitled quota × price (a
fixed fee). Usage beyond or without an entitlement is billed as pay per use
and flagged; sites without a subaccount are listed, unbilled. Prices are not
versioned: a price change also applies to earlier months when they are
viewed again.

```bash
./build/platform-open landscape                      # the tree with costs
./build/platform-open landscape show subaccount:shop-prod
./build/platform-open landscape check                # problems and advice; exit 1 on errors
./build/platform-open landscape billing --month=2026-11 --csv > billing.csv
```

**Firewall, network traffic, IP lists.** Every request passes, in this order:

1. **IP allow / deny lists** (always enforced). A rule is an address or CIDR
   network (IPv4 or IPv6) on the allow or the deny list, for one area: the
   management pages (`admin`: sign-in, `/status`, `/sites`, …, the Fiori app),
   the APIs (`api`: REST, OData, `/api`, `/metrics`) or everything (`all`,
   including the public site). A matching deny rule blocks. Once an area has
   allow rules, only the listed networks reach it, so the allow list works as
   a whitelist. Rules are stored with the domain's data (`iprules.json`) and
   managed under `/security` or with `firewall …` on the CLI. Changes that
   would lock out the person making them are refused; the CLI always works
   and a running server picks its changes up within 5 seconds.
2. **Bans**: `banAfterViolations` firewall findings within 10 minutes ban an
   address for `banMinutes`; administrators can also ban and unban by hand.
3. **Rate limit**: `rateLimitPerMinute` requests per address and minute (429).
4. **Web application firewall**: checks the method, URI, path and
   User-Agent, and the values of query parameters and URL-encoded form
   fields (not uploads, not password fields), for protocol abuse (null bytes,
   double encoding, overlong URIs), directory traversal, probes for software
   the platform does not run (`/.env`, `/wp-login.php`, `*.php`, …), attack
   tools (sqlmap, nikto, …), SQL injection, cross-site scripting and
   command/code injection (including `${jndi:…}`).

Steps 2–4 follow `firewallMode`: `block` refuses (403, JSON for API paths),
`detect` only logs and counts (try it first when the patterns may meet unusual
legitimate input), `off` leaves only the IP lists. Addresses on an allow list
are exempt from automatic bans and the rate limit but are still inspected.
Every finding is logged (`[firewall] …`) and shown under `/security`, together
with the traffic per client address (requests, bytes in and out, errors,
blocks, last request) and per minute; `/metrics` adds
`neko_network_bytes_total`, `neko_firewall_events_total`,
`neko_firewall_blocked_total` and `neko_firewall_bans`. Traffic figures and
bans are kept in memory since the start.

Behind a reverse proxy (the approuter, nginx, a load balancer) every request
seems to come from the proxy. List it in `trustedProxies`: the platform then
takes the client from `X-Forwarded-For` (the last entry that is not a trusted
proxy, so a forged first entry does not help). Never list proxies you do not
control.

```bash
./build/platform-open firewall allow 10.0.0.0/8 --scope=admin --note="office"
./build/platform-open firewall deny 203.0.113.0/24 --scope=all
./build/platform-open firewall check 192.0.2.10
./build/platform-open firewall rules
```

Further settings: `sessionIdleMinutes` (default 60, `NEKO_SESSION_IDLE_MINUTES`).
Five failed sign-ins for one user name from one address lock it for 15 minutes.

Two domains side by side, carrying a package upwards:

```bash
dub build --config=open && dub build --config=secret
./backend/build/platform-open &                  # :8080
./backend/build/platform-secret &                # :8083
./backend/build/platform-open transfers export --name=feed --target=secret \
    --payload='{"orders": 3}' --out=feed.json
./backend/build/platform-secret transfers import feed.json
```

The same executable is also the **command-line interface** — any argument
other than `serve` runs a command against the instance's data directory:

```bash
./backend/build/platform-open help
./backend/build/platform-open services register --name=billing --url=http://localhost:9000 --activate
./backend/build/platform-open services list
./backend/build/platform-open overview
```

## Frontend

UI5 is always loaded from the platform's own origin (`resources/`), never from
a CDN: isolated domains have no internet access, and the backend sends a strict
Content-Security-Policy.

```bash
cd frontend && npm install
npm start          # ui5 serve on :8090, proxies /odata and /rest to :8080
npm run start:mock # standalone with the OData mock server (localService/)
npm run build      # self-contained dist/ incl. the OpenUI5 runtime
npm run lint       # UI5 linter
```

The backend serves `frontend/dist` automatically when it exists (else
`frontend/`, which only works with `npm start`). Unit tests (QUnit) and OPA
journeys are in `frontend/test/` (`npm test`; OPA needs `npm run start:mock`).

## Configuration

Precedence, lowest to highest: compiled defaults → config file → environment
variables → `VCAP_SERVICES`.

The config file is `NEKO_CONFIG_FILE`, else the first of
`config/default.{json,yaml,yml}` and `backend/config/default.{json,yaml,yml}`
(also looked up next to the binary). Top-level keys apply to all domains; a
`"domains": {"secret": {…}}` section overrides per domain — see
[backend/config/default.json](backend/config/default.json).

| Key | Env | Default | Meaning |
| --- | --- | --- | --- |
| `host` | `NEKO_HOST` | `127.0.0.1` | bind address |
| `port` | `NEKO_PORT`, `PORT` | 8080 + level | open 8080 … secret 8083 |
| `transport` | `NEKO_TRANSPORT` | `tcp` | `tcp` or `unix` |
| `unixSocketPath` | `NEKO_UNIX_SOCKET` | `/tmp/neko-platform-<domain>.sock` | for `transport: unix` |
| `storage` | `NEKO_STORAGE` | `file` | `file` (JSON in `<dataDir>/<domain>`) or `memory` |
| `dataDir` | `NEKO_DATA_DIR` | `data` | shared by server and CLI |
| `frontendDir` | `NEKO_FRONTEND_DIR` | auto | Fiori app directory; `none` = off |
| `enforceScopes` | `NEKO_ENFORCE_SCOPES` | `false` | writes need the XSUAA `…Admin` scope |
| `healthCheckIntervalSeconds` | `NEKO_HEALTH_INTERVAL` | `0` (60 in default.json) | background health probes; 0 = off |
| `healthTimeoutSeconds` | `NEKO_HEALTH_TIMEOUT` | `5` | per probe |
| `maxPayloadBytes` | `NEKO_MAX_PAYLOAD` | 10 MiB | per transfer package |
| `logLevel` | `NEKO_LOG_LEVEL` | `info` | `trace`, `debug`, `info`, `warn`, `error` |
| `logDir` | `NEKO_LOG_DIR` | `<dataDir>/<domain>/logs` | log files; `none` = console only (default with `memory` storage) |
| `logRetentionDays` | `NEKO_LOG_RETENTION_DAYS` | `14` | older log files are removed; 0 = keep |
| `accessLog` | `NEKO_ACCESS_LOG` | `true` | one log line and NDJSON record per request |
| `metricsToken` | `NEKO_METRICS_TOKEN` | – | bearer token for `/metrics`; unset = local clients only |
| `maxUploadBytes` | `NEKO_MAX_UPLOAD` | 50 MiB | per uploaded file |
| `siteQuotaBytes` | `NEKO_SITE_QUOTA` | `0` | bytes per site; 0 = no quota |
| `defaultLanguage` | `NEKO_DEFAULT_LANGUAGE` | `en` | language of the default site created on the first start |
| `firewallMode` | `NEKO_FIREWALL_MODE` | `block` | `block`, `detect` (log only) or `off` (IP lists only) |
| `rateLimitPerMinute` | `NEKO_RATE_LIMIT` | `600` | requests per client address and minute; 0 = off |
| `banAfterViolations` | `NEKO_BAN_AFTER` | `20` | firewall findings within 10 minutes that ban an address; 0 = never |
| `banMinutes` | `NEKO_BAN_MINUTES` | `15` | length of an automatic ban |
| `trustedProxies` | `NEKO_TRUSTED_PROXIES` | – | comma-separated addresses / CIDR whose `X-Forwarded-For` is trusted |

On Cloud Foundry, bind a user-provided service named or tagged
`neko-platform-config`; its credentials use the same keys.

## Security notes

- **Trust boundary is the approuter.** With `enforceScopes`, the backend reads
  the scopes from the bearer token but does **not verify its signature** —
  the approuter (XSUAA) does. Do not expose the backend directly when relying
  on scopes, or add JWT verification first.
- **Content-Security-Policy.** API responses get `default-src 'none'`; UI pages
  get `default-src 'self'` plus `style-src 'unsafe-inline'`, which UI5 needs
  for inline style attributes.
- **No CSRF tokens in the backend.** CSRF protection is done by the approuter
  (`csrfProtection` in `xs-app.json`).
- **Storage on CF is ephemeral.** The JSON file storage and uploaded files
  live on the container disk; use a persistent volume or another storage
  adapter (`IBlobStore`, `IDocumentStore`) for real data.
- **Uploaded files** never decide their own content type, are stored under
  generated ids (client file names never reach the file system), and are
  served with `nosniff`, a sandboxing CSP and `attachment` for anything that
  is not safe to render.

## Tests

```bash
dub test --config=open           # unit tests (domain rules, use cases, adapters)
BIN=$PWD/build backend/tests/smoke.sh   # end-to-end: CLI, two domains, unix socket, scopes, OData,
                                        # roles, sites, uploads, monitoring, firewall, IP lists,
                                        # landscape, billing
```

## Deployment (SAP BTP, Cloud Foundry)

```bash
NEKO_DOMAIN=restricted mbt build
cf deploy mta_archives/neko-platform_1.0.0.mtar
```

Deploy each domain into its own space. Local approuter: copy
`approuter/default-env.example.json` to `approuter/default-env.json` (never
committed), fill in the XSUAA credentials, `cd approuter && npm install && npm run start:local`.
