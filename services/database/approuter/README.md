# hdb approuter

Single entry point on SAP BTP Cloud Foundry. XSUAA protects the Fiori app (`/`) and the admin console (`/admin`);
`/api/v1` and `/odata/v4` are passed through to the backend without XSUAA, because the database authenticates every
request with its own users, roles and Bearer tokens (the Fiori app signs in against `/api/v1/auth/login`).

Local: `npm install`, fill `default-env.json` (never committed), start the backend on port 8080, then
`npm run start:local` and open http://localhost:5000.
