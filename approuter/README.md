# Approuter

Single entry point on SAP BTP: XSUAA login, scope checks per route, CSRF
protection and forwarding to the backend destination `neko-platform-srv`.
The Fiori app is served from `resources/` — a self-contained build
(`npm run build:ui`) that includes the OpenUI5 runtime, so no CDN is needed.

| Route | Target | Scope |
| --- | --- | --- |
| `/health` | backend | none |
| `/odata/v4/platform/…` | backend | GET/HEAD: Viewer or Admin, others: Admin |
| `/rest/v1/…`, `/api/v1/…` | backend | GET: Viewer or Admin, others: Admin |
| `/status` | backend | Viewer or Admin |
| everything else | `resources/` | Viewer or Admin |

Local run: copy `default-env.example.json` to `default-env.json` (contains
secrets, git-ignored), fill in the credentials of an XSUAA instance created from
`xs-security.json`, start the backend on :8080, then
`npm install && npm run start:local` → http://localhost:5000.
