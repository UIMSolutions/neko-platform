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
| `/login` | sign-in for the server-rendered pages |
| `/status` | status page (Beer CSS + htmx, all assets embedded — works in isolated domains) |
| `/users`, `/account` | user management (administrators), own password |
| `/index.html` | Fiori cockpit (needs a frontend build, see below) |
| `/rest/v1/…` | REST API |
| `/odata/v4/platform/$metadata` | OData v4 service for Fiori |
| `/health`, `/api/v1/info` | liveness, effective configuration |

**Sign-in.** Each domain has its own web user accounts (stored with its data).
On the first start without accounts the server creates the administrator
`adminUser` (default `admin`) with `adminPassword` / `NEKO_ADMIN_PASSWORD`; if
none is set, it generates a password and prints it once in the log. Locked out?
Use the CLI on the same data directory:

```bash
./build/platform-open users list
echo 'a-new-password' | ./build/platform-open users passwd admin
./build/platform-open users add --name=ops --role=admin    # password from stdin
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
- **Storage on CF is ephemeral.** The JSON file storage lives on the container
  disk; use a persistent volume or another storage adapter for real data.

## Tests

```bash
dub test --config=open           # unit tests (domain rules, use cases, adapters)
backend/tests/smoke.sh           # end-to-end: CLI, two domains, unix socket, scopes, OData
```

## Deployment (SAP BTP, Cloud Foundry)

```bash
NEKO_DOMAIN=restricted mbt build
cf deploy mta_archives/neko-platform_1.0.0.mtar
```

Deploy each domain into its own space. Local approuter: copy
`approuter/default-env.example.json` to `approuter/default-env.json` (never
committed), fill in the XSUAA credentials, `cd approuter && npm install && npm run start:local`.
