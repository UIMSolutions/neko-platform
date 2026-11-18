# neko.database

In-memory column database built with vibe.d using hexagonal architecture.

    domain/        Value, ColumnTable (Column Store)
    application/   Ports + SqlService (Mini-SQL-Parser/Executor)
    adapters/
      inbound/     REST (vibe.d)
      outbound/    InMemoryTableRepository
    app.d          Composition Root

Start: `dub run`

    curl -X POST localhost:8080/sql -H 'Content-Type: application/json' \
      -d '{"statement":"CREATE TABLE orders (id INTEGER, customer VARCHAR(40), amount DECIMAL)"}'
    curl -X POST localhost:8080/sql -H 'Content-Type: application/json' \
      -d '{"statement":"INSERT INTO orders VALUES (1, '\''ACME'\'', 99.5)"}'
    curl -X POST localhost:8080/sql -H 'Content-Type: application/json' \
      -d '{"statement":"SELECT SUM(amount) FROM orders WHERE id >= 1"}'

## Data types

Each column type corresponds to a primitive EDM type from OData v4. In `CREATE TABLE` and the REST API, the SQL name,
a synonym or the EDM name may be used, regardless of case: `CREATE TABLE t (a Edm.Int16, b SMALLINT)`.

| SQL | Synonyms | EDM | SQL literal |
| --- | --- | --- | --- |
| `BOOLEAN` | `BOOL` | `Edm.Boolean` | `TRUE`, `FALSE` |
| `TINYINT` | `BYTE` | `Edm.Byte` | `255` (0 to 255) |
| `SBYTE` | | `Edm.SByte` | `-128` (-128 to 127) |
| `SMALLINT` | `INT16` | `Edm.Int16` | `32767` |
| `INT32` | | `Edm.Int32` | `2147483647` |
| `INTEGER` | `INT`, `BIGINT`, `INT64` | `Edm.Int64` | `42` |
| `REAL` | `SINGLE` | `Edm.Single` | `0.1` |
| `DECIMAL` | `DOUBLE` | `Edm.Double` | `1.5` |
| `NUMERIC` | | `Edm.Decimal` | `12345678901234567890.55` |
| `VARCHAR` | `NVARCHAR`, `TEXT` | `Edm.String` | `'Text'` |
| `BLOB` | `BINARY`, `VARBINARY` | `Edm.Binary` | `X'00FF'` or `'00FF'` |
| `DATE` | | `Edm.Date` | `'2026-11-06'` |
| `TIMESTAMP` | `DATETIMEOFFSET` | `Edm.DateTimeOffset` | `'2026-11-06T12:30:00+01:00'` |
| `TIME` | `TIMEOFDAY` | `Edm.TimeOfDay` | `'12:30:00'` |
| `DURATION` | | `Edm.Duration` | `'P1DT2H'` |
| `GUID` | `UUID` | `Edm.Guid` | `'01234567-89ab-cdef-0123-456789abcdef'` |
| `GEO` | `GEOMETRY`, `ST_GEOMETRY` | `Edm.Geometry` | `'POINT(13.4 52.5)'` |
| `GEOGRAPHY` | | `Edm.Geography` | `'POINT(13.4 52.5)'`, longitude and latitude in degrees |
| `LINK` | `URL` | `Edm.String` | `'https://example.org/a'` |

`LINK` is the only addition: EDM has no URL type, so it is exposed as `Edm.String`. `http`,
`https`, `ftp` and `mailto` are allowed; the admin interface displays values as clickable links.

Be careful with `DECIMAL`: the name is retained for compatibility with existing data, but the type is a double. Use
`NUMERIC` for exact decimal values, such as monetary amounts.

    CREATE TABLE orte (id GUID, aktiv BOOLEAN, preis NUMERIC, foto BLOB, lage GEOGRAPHY, seit TIMESTAMP, web LINK)
    INSERT INTO orte VALUES ('01234567-89ab-cdef-0123-456789abcdef', TRUE, 19.99, X'89504E47',
      'POINT(13.4 52.5)', '2026-11-06T12:30:00+01:00', 'https://example.org')
    SELECT id FROM orte WHERE aktiv = TRUE AND seit >= '2026-01-01T00:00:00Z' ORDER BY preis

Values are validated and normalized when written, including when files and backups are loaded:

- `TIMESTAMP` is converted to UTC and stored with seven fractional digits; the original offset is lost.
- `DURATION` supports only days through seconds, as in EDM; `PT36H` becomes `P1DT12H`. Values are sorted by duration.
- `NUMERIC` is exact and sorts numerically, but `SUM` and `AVG` use double arithmetic and round.
- `GEO` and `GEOGRAPHY` accept WKT for `POINT`, `LINESTRING` and `POLYGON`, in 2D only. Spatial functions such as
  distance and intersection are unavailable, as are `Multi*` geometries and collections.
- `SUM` and `AVG` work only on numbers; `LIKE` works only on types stored as text, not on numbers, `BOOLEAN`
  or `DURATION`.

`Edm.Stream` is not supported: it is media content with its own address, not a column value. Use `BLOB` for binary data.
Internally and through the REST API, `BLOB` is hexadecimal text; this doubles its size, so it is unsuitable for large files.

The REST API transmits `BOOLEAN` as a JSON boolean, `NUMERIC` as text to avoid losing digits, `GEO` as WKT
and `BLOB` as hexadecimal text. OData uses the formats defined by its specification; see below.

## REST API v1

Typed vibe.d interfaces in `presentation/rest` (`interfaces.d`, `models.d`, `services.d`), registered by
`registerHdbRestApi`. Clients can be generated from the interfaces: `new RestInterfaceClient!ITableRestApi(url)`.

| Method and path | Purpose |
|---|---|
| `GET /api/v1/health` | Health |
| `GET /api/v1/stats` | Statistics for all tables |
| `POST /api/v1/checkpoint` | Write a checkpoint |
| `GET /api/v1/merge` | Delta merge status |
| `POST /api/v1/merge` | Start a delta merge (202) |
| `POST /api/v1/sql` | `{"statement": "...", "transaction": "<id>"}`, ID also accepted in the `X-Transaction-Id` header |
| `GET /api/v1/tables` | Table names |
| `POST /api/v1/tables` | `{"name": "t", "columns": [{"name": "id", "type": "INTEGER"}]}` |
| `GET /api/v1/tables/:name` | Columns and statistics |
| `DELETE /api/v1/tables/:name` | Delete a table |
| `GET /api/v1/tables/:name/rows` | Rows; parameters `where`, `sort`, `desc`, `limit` (1 to 1000, default 100), `offset` |
| `POST /api/v1/tables/:name/rows` | `{"values": [1, "a", null]}`, one value per column |

Errors: `{"statusMessage": "..."}` with 400 (invalid SQL, locked database) or 404 (unknown table).
Also available: `GET|PUT /api/v1/network`, `PUT /api/v1/tenants/:name/networks` (see Allowed networks),
`GET|PUT|DELETE /api/v1/replication…` (see Replication), `POST /api/v1/auth/login|logout|password`, `GET /api/v1/auth/me` and `GET|POST /api/v1/users`,
`PUT|DELETE /api/v1/users/:name`, `POST /api/v1/users/:name/password`, `PUT /api/v1/users/:name/grants`,
`GET /api/v1/roles`, `PUT|DELETE /api/v1/roles/:name` (see Users and permissions), and for system administrators
`GET|POST /api/v1/tenants` and `PUT|DELETE /api/v1/tenants/:name` (see Tenants). Missing authentication returns 401,
insufficient permissions return 403. The endpoints without `/api/v1` (`adapters/inbound/rest_api.d`) remain available
and also require a bearer token.

## OData v4

OData 4.0 is available under `/odata/v4` (`presentation/odata`); tables are entity sets. Bearer-token authentication and
roles apply as they do to all other interfaces.

    curl localhost:8080/odata/v4/\$metadata -H "Authorization: Bearer $TOKEN"
    curl "localhost:8080/odata/v4/orders?\$filter=amount%20gt%2010&\$orderby=id%20desc&\$top=5&\$count=true" -H "Authorization: Bearer $TOKEN"
    curl -X PATCH "localhost:8080/odata/v4/orders(1)" -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d '{"amount": 12.5}'

- Reading: service document, `$metadata` (CSDL/XML), `/orders`, `/orders/$count`, `/orders(1)`, `/orders(1)/name`, `/orders(1)/name/$value`.
- Writing: `POST`, `PATCH`, `PUT` (missing properties become NULL), `DELETE`; `Prefer: return=minimal|representation`.
- Options: `$filter`, `$select`, `$orderby`, `$top`, `$skip`, `$count`, `$format=json`. At most 1000 rows per response,
  followed by `@odata.nextLink`.
- `$filter`: `eq ne gt ge lt le`, `and or not`, parentheses, `null`, `contains`, `startswith`, `endswith`. A property is
  compared with a literal. NULL behaves as in OData 4.0: `a ne 1` also matches rows where `a` is NULL.
- Not implemented; returns 501: `$expand`, `$search`, `$apply`, `$compute`, `$batch`, additional functions and arithmetic in
  `$filter`. There are no ETags or relationships between tables.

Types: see [Data types](#data-types). `Edm.Binary` is Base64url; `/$value` returns raw bytes. `Edm.Geometry` and
`Edm.Geography` are GeoJSON (`{"type":"Point","coordinates":[13.4,52.5]}`); WKT text is also accepted when writing because
the UI5 client can only change properties using simple values. With `IEEE754Compatible=true` in `Accept` or `Content-Type`,
`Edm.Int64`, `Edm.Decimal` and `@odata.count` are text in both directions. Without it, `Edm.Decimal` is a JSON number
with all digits when read; when writing, only text remains exact.

Literals in `$filter`: `true`, `2026-11-06`, `2026-11-06T12:30:00Z`, `12:30:00`, unquoted GUIDs, plus
`duration'P1D'`, `binary'AAEC'`, `geometry'SRID=0;Point(1 2)'` and `geography'SRID=4326;Point(1 2)'`. `contains`, `startswith`
and `endswith` work only on `Edm.String`.

Keys: tables have no primary key, so an `id` column (integer, `VARCHAR` or `GUID`) serves as the key.
The core does not enforce uniqueness: `POST` rejects existing keys, but if a key occurs more than once
(for example after SQL changes), requests targeting it return 409 rather than changing multiple rows. Tables without `id`
expose the computed property `__rowid`. This is only the position in the result; individual rows cannot be addressed (501).
Tables or columns whose names are not valid OData identifiers (such as `1a`) do not appear in the service.

## Fiori frontend

OpenUI5 application using the Fiori 3 design (`sap_fiori_3`) at `http://localhost:8080/ui5/`, with sources in `public/ui5/`.
It communicates only with `/odata/v4` and authentication (`/api/v1/auth`) and requires no build step.

- `FlexibleColumnLayout`: tables, rows, details. Links such as `#/tables/orders/rows/1` can be shared and reloaded.
- Side navigation (`sap.tnt.ToolPage`) with a hamburger button in the ShellBar: tables, statistics, backups (administrators
  only), help and admin console. It collapses to a toolbar and closes after selection on narrow screens.
- Language in the profile menu: English or German, stored in `localStorage`. Without a selection, the browser language
  is used. This does not affect the admin interface or server error messages.
- Search, sorting, a progressively loaded list, and row creation, editing and deletion. Columns come from `$metadata`, so
  new tables require no client changes. Creating tables and managing users remain in the admin interface.
- The model uses the `$direct` group because the service does not support `$batch`: each change is a separate request.
  When saving, each changed field is sent as a separate `PATCH`, so changes to multiple fields in a row are not atomic.
- The token is stored in `sessionStorage` and expires with the browser tab. OpenUI5 is loaded at a fixed version (1.148.10,
  maintained until Q3/2027) from the `sdk.openui5.org` CDN. This script has access to the token; to operate without an
  external CDN, serve the library yourself and change the URL in `public/ui5/index.html`.
- `public/ui5/` is accessible without authentication and must therefore contain no data or secrets.

## Administration interface

`http://localhost:8080/admin` (Adapter `adapters/inbound/admin_web.d`, Templates in `views/`, Skript in `public/admin.js`).

- Dashboard: metrics per table, trigger delta merges and checkpoints, create tables.
- Table view: filtering (WHERE), sorting, pagination, creating, editing and deleting rows, CSV export,
  emptying or deleting a table, storage statistics per column.
- SQL console: multiple statements separated by `;`, stopping at the first error; `BEGIN` persists across executions.
- Statistics (`/admin/stats`): storage metrics per column for all tables. Help (`/admin/help`): usage, SQL, data types.

Tables have no primary key. Editing or deleting a row therefore affects all rows with identical values; the interface
reports the number affected.

The interface hides actions not permitted by the role, but authorization is always decided on the server.

## Admin client (GTK)

A standalone desktop program `hdb-admin` based on GtkD (GTK 3), with sources in `source/neko/database/presentation/gui`.
It communicates with the server only through the REST API, using the same authentication and permissions as any other
client, and contains no server code (no vibe.d or OpenSSL).

    dub build --config=gui                      # produces ./hdb-admin
    ./hdb-admin --server=http://localhost:8080  # or HDB_URL=... ./hdb-admin
    dub test --config=gui                       # API client tests

Runtime requirements: GTK 3 and libcurl. After login (server, tenant, user, password), the sidebar shows only what
the user's permissions allow:

| Page | Permission | Contents |
|---|---|---|
| Tables | Table permissions | Tables and rows, WHERE filter, pages of 100 rows |
| SQL Console | Same as SQL | Statements with Ctrl+Enter; `BEGIN` holds the transaction until `COMMIT`/`ROLLBACK` |
| Statistics | – | Storage type and rows per visible table |
| Backups | `manageBackups` | Create, restore, delete |
| Audit log, Event log | `viewLogs` (settings: `manageLogs`) | Filter and page through entries, double-click for the full entry; Settings… |
| Application log | As above, only in the server scope | Technical server messages |
| Users | `manageAccess` | Create, assign roles, enable/disable, reset passwords, delete |
| Tenants | `viewTenants`/`manageTenants` | Only in the `system` scope: create, change and delete tenants |

- When the session ends (expired, password changed, network not allowed), the client prompts for login again.
- Requests are synchronous, with a 5-second connection timeout and a 120-second total timeout; the window does not
  respond while a request is running.
- Roles, table grants, allowed networks, replication and the backup schedule are currently available only in the
  browser administration interface.
- Without a desktop, the client can be viewed in a browser: run `broadwayd :5 &` and
  `GDK_BACKEND=broadway BROADWAY_DISPLAY=:5 ./hdb-admin`, then open http://localhost:8085.

Structure: `api.d` is the @safe REST API client behind the `IHttpTransport` port (tested with a fake),
`transport.d` is the actual libcurl transport, and `widgets.d`, `pages.d`, `login.d` and `window.d` provide the GTK interface.
GtkD is not @safe, so the interface modules remain @system and contain no logic of their own.

## Unix Domain Socket

With `UNIX_SOCKET=/run/hdb/hdb.sock`, the server accepts requests over a Unix domain socket as well as HTTP
(`presentation/unix`). Without this variable, there is no socket. Paths and JSON are the same as for the REST API:
`/api/v1/health`, `/auth/login`, `/auth/logout`, `/sql`, `/tables`, `/stats`, `/checkpoint` and `/merge`.

    POST /api/v1/sql
    Authorization: Bearer <token>
    Content-Length: 37

    {"statement":"SELECT COUNT(*) FROM t"}

Response: a `STATUS 200` line, headers including `Content-Length`, a blank line and the body. A connection serves multiple sequential requests.

- The socket has permissions 0600. This does not replace authentication: every request needs a token, and roles apply as with HTTP.
- A body is limited to 16 MB and headers to 64 KB. An invalid message receives 400 or 413, after which the connection
  closes. An idle connection closes after 5 minutes.
- A stale socket after a crash is replaced at startup. If it still responds or the path contains something other than a
  socket, startup fails and nothing is deleted.

## Operating modes

| Mode | Start | Purpose |
|---|---|---|
| Embedded | Library, `dub build --config=library` | Database in your own D program, without networking or authentication |
| Single tenant | `HDB_MODE=single ./hdb` | One server with exactly one database, without a tenant login field or system scope |
| Multi-tenant | `./hdb` (default, `HDB_MODE=multi`) | One server with multiple isolated tenants, see [Tenants](#tenants) |
| Distributed (gateway) | `HDB_MODE=gateway ./hdb` | One entry point in front of multiple hdb servers, each tenant on one server |

`GET /api/v1/info` (no authentication) reports the operating mode, for example `{"mode":"single","tenantLogin":false}`.
The Fiori client, admin interface and GTK client use it to hide the tenant login field. An invalid `HDB_MODE` value
or incompatible configuration aborts startup with exit code 1.

### Embedded

The database runs in the application's process: no HTTP, users or roles; anyone calling the API has all permissions.
No vibe.d event loop is needed; as on the server, delta merges run in a separate thread.

    // Application's dub.sdl
    dependency "hdb" path="../hdb"
    subConfiguration "hdb" "library"

```d
import neko.database.embedded;

auto db = HdbDatabase.open("data/mydb");     // or HdbDatabase.inMemory()
scope (exit) db.close();                     // persists the current state
db.execute("CREATE TABLE t (k INTEGER, name VARCHAR) USING FILE");
auto tx = db.begin();
scope (failure) tx.rollback();
tx.execute("INSERT INTO t VALUES (1, 'a')");
tx.commit();
auto result = db.execute("SELECT k, name FROM t");   // QueryResult: columns, rows (Value)
auto backup = db.backup("vor-umbau");               // also backups(), restore(name), removeBackup(name)
```

The directory has the same layout as a server tenant (`tables/`, `hdb.log`, `backups/`): once copied to
`TENANTS_DIR/<mandant>` and created as a tenant, it belongs to the server, and vice versa. Only one process may open a
directory at a time. `inMemory()` supports only in-memory tables and requires a directory for backups
(`inMemory("backups")`). The library contains all server code and therefore depends on vibe.d, but does not start it.

### Single tenant

`HDB_MODE=single` operates only the `default` tenant:

- Login does not ask for a tenant; a tenant specified through the API is ignored.
- There is no system scope: `sysadmin` is not created and users in the `system` scope cannot log in.
  Users, roles, table grants, time-limited permissions, allowed networks, backups and replication work as usual.
- As in multi-tenant mode, data is stored under `data/tenants/default`, so switching to `HDB_MODE=multi` requires
  no migration. Switching back to `single` is possible only if no tenant other than `default` exists; otherwise
  startup fails with a message so that no data becomes inaccessible.

### Distributed (gateway)

The gateway has no data or users of its own. It accepts each request and forwards it to the tenant's hdb server
(backend); the backend checks permissions as it would for direct access.

    HDB_MODE=gateway GATEWAY_CONFIG=data/hdb-gateway.json PORT=8080 ./hdb

```json
{
  "backends": { "eu": "http://10.0.0.1:8080", "us": "https://us.example:8443" },
  "tenants":  { "default": "eu", "acme": "us" },
  "fallback": "eu"
}
```

- **Login:** The gateway forwards it to the tenant's backend and returns its token with a prefixed identifier
  (`us.<token>`, likewise in the admin interface cookie). Subsequent requests use the identifier to reach the same
  backend, without the identifier. A token never goes to another backend: an incorrect identifier results in 401.
- **Tenants without an entry** go to `fallback`. Without `fallback`, their login fails. Public pages, including the login
  form and Fiori client, also come from `fallback` (or the first backend by name if there is no fallback).
- **System administrators:** Each backend has its own system scope. Log in through the gateway with tenant
  `system@<backend>`, for example `system@us`; `system` alone goes to the backend specified by `tenants` or `fallback`.
- **New tenant:** A system administrator creates it on a backend; then it must be added to `tenants` unless it is on
  `fallback`. The file is reloaded without restarting (at most once per second); if invalid, the previous configuration
  remains active and the log explains why.
- **Client address:** The gateway appends it to `X-Forwarded-For`. Backends must include the gateway in
  `TRUSTED_PROXIES`, otherwise they check allowed networks against the gateway's address. The client's Host header
  is preserved so that the admin interface recognizes forms as same-origin.
- **Moving a tenant:** Create the tenant on the new backend and configure it as a replication target of the old one
  (see [Replication](#replication)), let it catch up, stop replication (making the target writable) and change the
  entry in `tenants`. Replication transfers only data: the tenant's users and roles must be created on the new backend.
  Existing sessions end when the tenant moves.

| Variable | Default | Meaning |
|---|---|---|
| `GATEWAY_CONFIG` | `data/hdb-gateway.json` | Configuration as above |
| `GATEWAY_CONNECT_SECONDS` | `5` | Timeout for connecting to a backend |
| `GATEWAY_READ_SECONDS` | `300` | Timeout for a response (long queries, backups) |
| `PORT`, `MAX_REQUEST_MB` | `8080`, `256` | As on the server |

If a backend is unreachable, the gateway responds with 502. Tenants on other backends are unaffected. The gateway
supports HTTP only; Unix sockets and replication continue directly between servers.

## Tenants

Each tenant has its own database: tables, statement log, backups, schedule and users. None of these are shared, nor is
an open transaction. Two tenants can have the same table and user names.

    data/hdb-tenants.json          List of tenants (TENANTS_FILE)
    data/hdb-users.json            Users of all tenants (USERS_FILE)
    data/tenants/<mandant>/        Tenant data (TENANTS_DIR)
        hdb.log                    Statement log
        tables/file, tables/json   Tables using FILE and JSON storage
        backups/                   Backups and schedule.json

Log in with a tenant using the tenant field in forms or the `tenant` field in the API. If omitted, `default` is used,
so existing scripts continue to work unchanged.

    curl -s localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
      -d '{"tenant":"acme","user":"admin","password":"..."}'

Only system administrators, i.e. administrators in the `system` scope, manage tenants. They log in with the `system`
tenant, create tenants with their first administrator, change display names, and deactivate or delete tenants. They
cannot access tenant data: SQL, OData, tables and backups return 403, and the administration interface shows them only
tenants, system users and their account. Tenant administrators manage everything else themselves, only within their tenant.

    curl localhost:8080/api/v1/tenants -H "Authorization: Bearer $SYSTOKEN" -H 'Content-Type: application/json' \
      -d '{"name":"acme","label":"Acme Corp","adminName":"admin","adminPassword":"..."}'
    curl -X PUT localhost:8080/api/v1/tenants/acme -H "Authorization: Bearer $SYSTOKEN" -H 'Content-Type: application/json' \
      -d '{"label":"Acme Corp","active":false}'
    curl -X DELETE localhost:8080/api/v1/tenants/acme -H "Authorization: Bearer $SYSTOKEN"

- Tenant names: 1 to 32 lowercase letters, digits, `_` and `-`, starting with a letter or digit. They form part of
  the login and directory name and cannot be changed. `system` is reserved.
- Deactivation immediately ends all tenant sessions and prevents new logins. Data and users remain.
- Only deactivated tenants can be deleted; deletion permanently removes users, data and backups.
- If data from a former tenant of the same name remains on disk, creation is rejected rather than adopting it.
- Login reports an unknown or deactivated tenant in the same way as an incorrect password.
- All tenants are loaded at startup and held in memory, as the single database was previously.

First startup: the `default` tenant is created with `ADMIN_USER` (default `admin`, password `ADMIN_PASSWORD`) and the
system administrator `SYSTEM_ADMIN_USER` (default `sysadmin`, password `SYSTEM_ADMIN_PASSWORD`). If no password is supplied,
one is generated and logged once. The system administrator is also created if the `system` scope has no users yet,
for example on the first startup after migration.

Migrating an existing installation: on first startup, `DATA_FILE`, `TABLES_DIR` and `BACKUP_DIR` move to
`TENANTS_DIR/default` (moved, not copied), and all existing users belong to `default`. Logins without a tenant work as
before. This happens only while `TENANTS_DIR/default` does not yet exist.

## Users and permissions

Every route requires authentication except `GET /health`, `GET /api/v1/health` and the login pages.

Permissions are assigned through roles (RBAC) at three levels:

| Level | Who | Permissions |
|---|---|---|
| Server | Users in the `system` scope | `viewTenants`, `manageTenants`, `manageAccess` (system users and roles), `viewLogs`, `manageLogs` |
| Tenant | A user's role, applies to all tables | `select`, `insert`, `update`, `delete`, `drop`, `create`, `transact`, `maintain`, `manageBackups`, `replicate`, `manageReplication`, `manageAccess`, `viewLogs`, `manageLogs`, `execute`, `manageProcedures` |
| Table | Grant: a role for one table | Only `select`, `insert`, `update`, `delete`, `drop` from the above |

Predefined, immutable roles ensure existing users retain their permissions:

| Scope | Role | Permissions |
|---|---|---|
| Tenant | `viewer` | `select`, `replicate`, `execute` |
| Tenant | `editor` | Also `insert`, `update`, `delete`, `transact` |
| Tenant | `admin` | All tenant permissions |
| `system` | `viewer` | `viewTenants` |
| `system` | `admin` | All server permissions |

Custom roles can be created with `manageAccess` at `/admin/roles` or through the API, per tenant or in the `system`
scope. A user has at most one tenant role (or none) and any number of table grants under
`/admin/users/<name>/grants`. Permissions are additive; there are no denials. A user without a role sees only granted tables.

    curl -X PUT localhost:8080/api/v1/roles/clerk -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"description":"Reads and adds rows","permissions":["select","insert"]}'
    curl localhost:8080/api/v1/users -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"name":"tina","password":"...","role":""}'
    curl -X PUT localhost:8080/api/v1/users/tina/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"grants":[{"table":"orders","role":"clerk"}]}'
    curl localhost:8080/api/v1/auth/me -H "Authorization: Bearer $TOKEN"   # resolved permissions, including per table

- The SQL core checks table permissions wherever a statement accesses a table: for each table in joins and before
  every change. A hidden table behaves like a missing one (403 or 404 with the same message as an unknown table);
  its existence is not disclosed.
- Table lists, statistics, OData `$metadata` and interfaces show only tables on which the user has permission, and
  only buttons the user may use.
- `create` and `transact` apply only tenant-wide: `BEGIN` locks all tables.
- Grants may name tables that do not yet exist, and apply again after `DROP` if a table of the same name is recreated.
- Role and grant changes take effect immediately, even in active sessions. A role can be deleted only when nobody uses it.
- Each scope must retain an active user with `manageAccess`; changes that would prevent this are rejected. This
  permission comes only from the tenant role, never from a table grant.
- Backups (`manageBackups`) and the replication stream (`replicate`) contain all tables: grant these permissions only
  to roles that may already read everything.
- Custom roles are stored in `ROLES_FILE` (default `data/hdb-roles.json`), and user roles and grants in `USERS_FILE`.

Only its owner can use an open transaction.

### Time-limited permissions

A user's additional roles (under `/admin/users/<name>/grants` or `PUT /api/v1/users/<name>/grants`) can be time-limited.
Without a table, such a role applies throughout the tenant, or on the server in the `system` scope, for example
"admin until Friday at 18:00":

    curl -X PUT localhost:8080/api/v1/users/vic/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"grants":[{"table":"","role":"admin","until":"2026-11-13T17:00:00Z"},
                     {"table":"orders","role":"editor","from":"2026-11-10T08:00","until":"2026-11-10T18:00"}]}'

- `from` (inclusive) and `until` (exclusive) are optional and in UTC; a missing time zone means UTC. Values are stored
  in canonical form (`2026-11-10T08:00:00Z`).
- Outside the interval, a grant has no effect. Permissions are resolved on every request: a grant starts and ends
  to the second, even in existing sessions.
- Responses report the state (`active`, `scheduled`, `expired`). Expired grants remain for traceability until removed
  ("Remove expired grants"); new expired grants cannot be created.
- Time-limited roles do not count toward the rule requiring an active user to retain `manageAccess`: only the permanent
  role counts.

### Allowed networks

Tenant administrators (`manageAccess`) configure the IP addresses and networks (IPv4/IPv6, CIDR) from which their
users may work under `/admin/network` or through the API. An empty list allows all addresses.

    curl localhost:8080/api/v1/network -H "Authorization: Bearer $TOKEN"     # list and own address
    curl -X PUT localhost:8080/api/v1/network -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"networks":["192.168.10.0/24","2001:db8::/32"]}'

- Checks run at login (after the password; disallowed addresses receive 403 with a message) and on every request. A token
  from another address is invalid there; the session remains valid for allowed addresses.
- A list excluding the caller's own address is rejected to prevent self-lockout. If tenant administrators are still
  locked out, system administrators (`manageTenants`) can reset the list on the tenant page or through
  `PUT /api/v1/tenants/<name>/networks`.
- The `system` scope is not restricted.
- Unix socket clients are treated as `127.0.0.1`. Replication targets need their address on the source's list.
- Behind a reverse proxy, specify `TRUSTED_PROXIES` (comma-separated addresses or networks). `X-Forwarded-For` is
  trusted only from these proxies; the last entry that is not a trusted proxy is used. Without the variable, the
  connection address is used, so behind a proxy the server sees only the proxy's address.
- Lists are stored in `TENANTS_FILE` (the `networks` field).

First startup: see Tenants. Change generated passwords under `/admin/account`; the variables are ignored afterwards.
If a tenant administrator's password is lost, another tenant administrator can reset it. If none remains, the tenant
can only be repaired through `USERS_FILE`.

    TOKEN=$(curl -s localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
      -d '{"user":"admin","password":"..."}' | jq -r .token)
    curl localhost:8080/sql -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"statement":"SELECT * FROM orders"}'

- Authentication: `/admin` uses a cookie (HttpOnly, SameSite=Strict); all REST routes use bearer tokens only. Tokens
  last 12 hours, are stored only as hashes in memory, and expire on restart, password change, deactivation or deletion.
- Passwords: at least 12 characters, PBKDF2-HMAC-SHA256 with 600,000 rounds. After 5 failed attempts the name is locked
  for 1 minute, even if it does not exist. An attacker can therefore temporarily block login for a name.
- Users of all tenants are stored in `USERS_FILE` (default `data/hdb-users.json`, permissions 0600), not in the statement
  log. A damaged file aborts startup. Backups must include this file.
- The log still contains all data in plaintext; permissions apply only to access over HTTP.
- Tokens, cookies and passwords travel in plaintext over HTTP: use TLS on networks. The cookie gets `Secure` when the
  proxy sets `X-Forwarded-Proto: https`.

Enforcement is centralized: `TenantDatabases` selects the logged-in tenant's database, where `SecuredSqlUseCase` wraps
the core. All inbound adapters see only `TenantDatabases`.
`SecurityGate` sets the identity for each request and allows only public paths without authentication.

## Table storage

    CREATE TABLE klein (id INTEGER, name VARCHAR) USING JSON

When creating a table, choose its storage in the admin form, using `USING`, or in the `storage` field of
`POST /api/v1/tables`. The default is `MEMORY`. Queries always run in memory; the difference concerns durability only.
Storage cannot be changed later; instead, recreate the table and copy the data.

| Storage | Repository | Persisted by | Write cost |
|---|---|---|---|
| `MEMORY` | `MemoryTableRepository` | Statement log (see Persistence) | One log line |
| `FILE` | `FileTableRepository` | `tables/file/<name>.tbl` (tab-separated text) | Entire file rewritten |
| `JSON` | `JsonTableRepository` | `tables/json/<name>.json` | Entire file rewritten |
| `BINARY` | `BinaryTableRepository` | `tables/binary/<name>.bin` (compact, with SHA-256) | Entire file rewritten |
| `BSON` | `BsonTableRepository` | `tables/bson/<name>.bson` (one BSON document) | Entire file rewritten |

Paths are inside the tenant directory (`TENANTS_DIR/<mandant>`, see Tenants). `RoutingTableRepository` distributes
tables; names are unique across all storage types. `GET /stats` and `GET /api/v1/stats` show `storage`.

- `FILE`, `JSON`, `BINARY` and `BSON` tables never appear in the statement log: each table has exactly one durable source.
- `BINARY`: little-endian, bit-exact numbers (int64, IEEE-754 double), UTF-8 text with length, exact decimals as text.
  A SHA-256 checksum appears at the end; a damaged file aborts startup. The layout is documented in a comment in
  `BinaryTableRepository`.
- `BSON`: `{format: "hdb-table", version: 1, name, columns: [{name, type}], rows: [[...], ...]}`. Integers are int64,
  `DOUBLE`/`REAL` are double, `BOOLEAN` is bool, everything else is string (including `DECIMAL`, to avoid losing digits).
  Readable with, for example, `bsondump tables/bson/<name>.bson`. Reading is strict: unknown BSON types, incorrect
  lengths or values incompatible with the column type abort startup. BSON allows at most 2 GB per file; MongoDB accepts
  documents up to 16 MB only.
- Writes happen at the commit point, after each statement or at `COMMIT`; `ROLLBACK` never reaches the file.
  Files are replaced using a temporary file, `fsync` and `rename`, leaving either the old or the new state.
- Every change rewrites the entire file. `MEMORY` is a better choice for large or frequently changed tables.
- A transaction spanning multiple files or a file and the log is not atomic if a crash occurs during `COMMIT`:
  files are written sequentially, with the log last.
- A damaged file or the same table name in two storage types aborts startup.
- Files are plaintext. Server backups must include `TENANTS_DIR`.

## Backup and restore

Only for the `admin` role, in the administration interface (`/admin/backups`), the Fiori frontend and through REST:

    curl -X POST localhost:8080/api/v1/backups -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d '{"label": "vor dem Update"}'
    curl localhost:8080/api/v1/backups -H "Authorization: Bearer $TOKEN"
    curl -o sicherung.hdbbak localhost:8080/api/v1/backups/<name>/content -H "Authorization: Bearer $TOKEN"
    curl -X POST --data-binary @sicherung.hdbbak localhost:8080/api/v1/backups/import \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/octet-stream'
    curl -X POST localhost:8080/api/v1/backups/<name>/restore -H "Authorization: Bearer $TOKEN"

- Backups belong to tenants: administrators see and create only their tenant's backups, restore replaces only its tables,
  and each tenant has its own schedule.
- A backup is a file (`*.hdbbak`, permissions 0600) in `TENANTS_DIR/<mandant>/backups`. It contains all tables from all
  storage types with schema, storage type and exact values, and ends with a SHA-256 checksum. It is not encrypted.
- Backup requires a quiescent state: it is rejected if a transaction is open. The database otherwise remains usable,
  but is locked during copying. A backup is held entirely in memory, including during upload and download.
- Restore replaces all tables. The file is fully validated first, then a `before-restore` safety backup is created
  automatically, allowing even a successful restore to be undone. If replacement fails, the old state is restored.
  A crash during replacement can leave a mixed state; restore the safety backup in that case. Safety backups are not
  automatically deleted.
- Users are not included in backups: restoring does not lock anyone out or bring back old passwords.
  `USERS_FILE` must be backed up separately.
- Uploaded files are untrusted. The checksum detects corruption, not forgery, so names, types and values are always
  validated. Uploading does not restore anything.
- `MAX_REQUEST_MB` (default 256) limits requests and thus upload size. Unauthenticated requests are limited to 64 KB.
- Backups are on the same disk as the data: copy them elsewhere as well to protect against disk failure.

Scheduling and retention are enabled by default: one backup every 24 hours, retaining 7 scheduled and 5 safety backups.
They can be configured in both interfaces and through `GET|PUT /api/v1/backups/schedule`, and are stored in the tenant's
`backups/schedule.json`.

    curl -X PUT localhost:8080/api/v1/backups/schedule -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"enabled": true, "intervalHours": 6, "keepScheduled": 28, "keepSafety": 5}'

- The first backup is created shortly after startup as soon as tables exist. Restarting does not reset the deadline.
  `BACKUP_TICK_SECONDS` (default 60) controls how often the server checks whether a backup is due.
- Retention deletes only `scheduled` and `safety` backups, oldest first and only after a successful new backup. Manual
  and uploaded backups always remain. The labels `scheduled` and `before-restore` are therefore reserved. Reducing
  retention takes effect immediately.
- If a scheduled backup fails, for example because a transaction is open, the interfaces and log report it; the next
  attempt follows after 5 minutes.
- Retention counts backups without inspecting their contents: an unnoticed incorrect state displaces all older scheduled
  states after `keepScheduled` runs. Create manual backups for important states.

## Replication

A tenant can be mirrored to another hdb server: one source, any number of targets, with changes flowing only from source
to target. The target first fetches a full snapshot and then every committed change, for all storage types (`MEMORY`,
`FILE`, `JSON`). A target can itself be a source (A -> B -> C).

Configure on the target, as an administrator of the target tenant, under `/admin/replication` or through the API. On
the source, a user with the `viewer` role is sufficient:

    curl -X PUT localhost:8081/api/v1/replication/source -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"url":"https://primary:8080","tenant":"default","user":"replica","password":"...","intervalSeconds":2}'
    curl localhost:8081/api/v1/replication -H "Authorization: Bearer $TOKEN"              # status
    curl -X POST localhost:8081/api/v1/replication/resync -H "Authorization: Bearer $TOKEN"  # fetch a full snapshot again
    curl -X DELETE localhost:8081/api/v1/replication/source -H "Authorization: Bearer $TOKEN"  # stop

- The first run replaces all tables of the target tenant. While replication runs, the target rejects writes (403),
  including `BEGIN` and restore; reads, backups and statistics remain available. Once stopped, the target retains its
  state and becomes writable again, for example to take over after a source failure.
- The source provides `GET /api/v1/replication/snapshot` (state in backup format, position in `X-Hdb-Epoch` and
  `X-Hdb-Sequence`) and `GET /api/v1/replication/changes?epoch=&since=&max=`. Each change is a single statement
  or a whole transaction; the target applies it as a unit. Rolled-back transactions never appear.
- The change stream exists only in memory. Restarting or restoring the source starts a new epoch, as does restarting
  the target: the target then fetches a full snapshot. This also happens if it falls further behind than the source's
  retained changes (`REPLICATION_RETAIN`, default 10000 per tenant), or if a change cannot be applied.
- The target reports source failures once in the log and `lastError`, then retries at the configured interval
  (at least 5 seconds) and catches up. It renews expired sessions itself.
- The source password is stored in plaintext in `TENANTS_DIR/<mandant>/replication.json` (permissions 0600) so the target
  can log in again. The API never returns it; an empty password when editing retains it, but only for the same source
  and user.
- The source is queried with the server's permissions. `REPLICATION_ALLOWED_HOSTS` (comma-separated) restricts allowed
  hosts; without it, tenant administrators may enter any http(s) address.
- Use TLS between servers on a network: otherwise credentials and data travel in plaintext.
- Users are not replicated, as with backups.

## Logs

Three logs, each with its own settings, which administrators can change in `hdb-admin` (the *Audit log*,
*Application log* and *Event log* pages, *Settings…* button) or through the REST API:

| Log | Contents | Categories |
|---|---|---|
| `audit` | Who did what and when, with address and outcome; failures with reason | `auth`, `users`, `roles`, `network`, `tenants`, `backups`, `replication`, `schema`, `data`, `maintenance`, `logs` |
| `event` | Operational events | `server` (startup, shutdown, initial setup), `backups` (scheduled backups), `replication` (state changes, errors) |
| `application` | Everything sent through `vibe.core.log` (including from vibe.d), with the reporting module | – |

- **Scopes:** Each tenant has its own audit and event logs with separate settings and sees only those logs. The server
  scope (`system`, or `default` in single-tenant mode) also has the application log and sees entries for all tenants
  (`tenant` filter). Entries for unknown tenants (such as login to a nonexistent tenant) go to the server scope.
- **Permissions:** `viewLogs` to read, `manageLogs` to configure. Both belong to the `admin` role in tenants and in
  the `system` scope and can be assigned to custom roles.
- **Settings per log:** on/off, minimum severity (`debug`, `info`, `warning`, `error`), retention in days (1–3650),
  maximum entries (100–1,000,000) and recorded categories. Defaults: audit 365 days / 50,000 without `data`,
  events 90 days / 20,000, application 30 days / 20,000 from `info`. Shorter retention takes effect immediately;
  otherwise the server cleans up hourly.
- **Always recorded:** Changes to log settings (category `logs`), including rejected changes and even when audit is off.
- **Audit severity:** Success `info`, failure `warning`; with minimum severity `warning`, only failures remain.
- **Never logged:** Passwords, tokens, row values (`data` records only table, verb and row count), and the password of
  a replication source. `SELECT`, `BEGIN`, `COMMIT` and `ROLLBACK` are not recorded; changes in a transaction are
  recorded when executed (even if later rolled back).
- **Storage:** `LOG_DIR` (default `data/logs`) with `audit.jsonl`, `event.jsonl`, `application.jsonl`, one JSON object
  per line, permissions 0600; settings in `LOG_SETTINGS_FILE` (default `data/hdb-logs.json`). A damaged settings
  file aborts startup; unreadable log lines are skipped. All entries are also held and searched in memory.
- An error writing an entry does not block an action.

REST (`kind` is `audit`, `application` or `event`):

    GET /api/v1/logs                        # logs for the current login, with settings and categories
    GET /api/v1/logs/:kind?severity=warning&category=auth&actor=ann&text=login&tenant=acme&from=2026-11-08T00:00&until=...&limit=200&before=<id>
    GET /api/v1/logs/:kind/settings
    PUT /api/v1/logs/:kind/settings         # {"enabled", "minSeverity", "retentionDays", "maxEntries", "categories"}

Entries are returned newest first with `total` (all matches); paginate using `before` = the smallest ID on the page.

Structure: `domain/types/logentry.d` (entry, settings, categories), `application/services/logging.d`
(`LogService`: filtering according to settings, search, retention), `application/services/audit.d` (decorators around
`IAccessUseCase`, `ITenantUseCase` and the data ports: the services themselves know nothing about auditing),
`adapters/outbound/file_log_store.d` and `adapters/inbound/application_log.d` (vibe logger buffering lines from all
threads and emitting them on the main thread).

## Persistence

Command log (write-ahead log) through the `IStatementLog` port, `FileStatementLog` adapter.
Every successful change to `MEMORY` tables (`CREATE`, `DROP`, `INSERT`, `UPDATE`, `DELETE`) is appended; `recover()` replays the log at startup.
After 1000 statements or via `POST /checkpoint`, the log is rewritten compactly.
File: `TENANTS_DIR/<mandant>/hdb.log`, one per tenant (see Tenants). `DATA_FILE` now specifies only the old location for migration.

## Column storage: dictionary + delta merge

Each column (`domain/column.d`) consists of a sorted main store (dictionary + codes) and a delta store (unsorted
dictionary + codes). `INSERT` goes into the delta. The delta merge rebuilds the sorted dictionary and rewrites all
codes; it runs in the background (see below), automatically at 1000 delta rows, via `POST /merge`, and once
synchronously after startup. `WHERE` is evaluated only per DISTINCT value, then codes are scanned. `GET /stats`
shows rows and DISTINCT values per column (main/delta).

## GROUP BY

    SELECT customer, COUNT(*), SUM(amount) FROM orders WHERE amount >= 10 GROUP BY customer

The grouping column, `COUNT(*)` and `SUM(x)` are allowed. The group is determined per DISTINCT dictionary key
(main and delta), not per row. Results are sorted by group value.

## Bitpacking

Main codes are stored in `domain/packed_vector.d`: each code occupies only `ceil(log2(distinct))` bits instead of 32.
`GET /stats` shows `mainBits` and `mainCodeBytes` per column.

## ORDER BY and additional aggregates

    SELECT n, MIN(q), MAX(q), AVG(w) FROM p WHERE q >= 1 GROUP BY n ORDER BY AVG(w) DESC, n
    SELECT n FROM p ORDER BY q DESC

- Aggregates: `COUNT(*)`, `SUM(x)`, `AVG(x)` (numeric only), `MIN(x)`, `MAX(x)` (also text); also without `GROUP BY`.
- `ORDER BY` with multiple keys, `ASC`/`DESC`. Without aggregation, any table column may be used for sorting,
  even if not selected. With aggregation: a result column, expression as in SELECT, or position (1-based).
- Sorting is stable. Without `ORDER BY`, groups are sorted by group value.
- Result columns are now named `COUNT` and, for example, `SUM(amount)`.
- Aggregates ignore NULL; with no values, `SUM`/`AVG`/`MIN`/`MAX` return NULL, and `COUNT` returns 0.

## HAVING, LIMIT, OFFSET

    SELECT g, SUM(v) FROM h GROUP BY g HAVING COUNT(*) >= 2 ORDER BY SUM(v) DESC LIMIT 10 OFFSET 20

- `HAVING expression op value`: the expression is an aggregate or grouping column; it need not appear in `SELECT`.
- `LIMIT n [OFFSET m]` applies after `ORDER BY`. `OFFSET` is available only with `LIMIT`.
- Order: WHERE, GROUP BY, HAVING, ORDER BY, LIMIT.

## UPDATE and DELETE

    UPDATE orders SET amount = 120.5, customer = 'ACME' WHERE id = 7
    DELETE FROM orders WHERE amount < 10

- `DELETE` marks rows in a deletion vector; all queries skip them.
- `UPDATE` is insert-only: the old row version is deleted and the new one goes into the delta (at the end of the table,
  so the order changes without `ORDER BY`).
- Deleted rows are physically removed during delta merge (`POST /merge`, after startup), automatically at 1000 deleted
  rows if they make up more than half the table. They are not written to the log at checkpoint.
- Both statements are logged and deterministically replayed at startup.
- `GET /stats` shows `rows` (live rows) and `deletedRows`.

## DROP TABLE

    DROP TABLE orders

Logged and replayed at startup. In a transaction, `ROLLBACK` restores the table and its data.

## JOIN

    SELECT c.name, SUM(o.amt) FROM customers c JOIN orders o ON c.id = o.cid
    WHERE o.amt >= 2 GROUP BY c.name ORDER BY SUM(o.amt) DESC

- `[INNER] JOIN table [alias] ON a = b`, including multiple joins in sequence (left-deep). Implemented as a hash join.
- The join result is a temporary column table with `alias.column` columns; WHERE, GROUP BY, HAVING, ORDER BY and
  aggregates run on it unchanged. Unqualified names work if unambiguous.
- An alias on a single table (`FROM orders o`) allows `o.column`.
- Equijoins only (INNER and LEFT). Self-joins require two different aliases.
- Both sides are copied for the join (O(rows) memory), but only rows remaining after WHERE pushdown (see below).

## NULL and LEFT JOIN

    SELECT c.name, COUNT(o.id) FROM customers c LEFT JOIN orders o ON c.id = o.cid GROUP BY c.name
    SELECT c.name FROM customers c LEFT JOIN orders o ON c.id = o.cid WHERE o.id IS NULL

- `LEFT [OUTER] JOIN`: unmatched left rows are retained, with NULL in the right columns.
- NULL literal in `INSERT` and `UPDATE ... SET x = NULL`; `WHERE x IS [NOT] NULL`.
- Comparisons with NULL are never true (`x = NULL` matches nothing; use `IS NULL`). NULL never joins to NULL.
- `COUNT(column)` counts only non-NULL values, `COUNT(*)` all rows. NULL forms its own `GROUP BY` group.
- `ORDER BY`: NULL sorts first (last with `DESC`). In JSON NULL appears as `null`, in the log as `NULL`.

## Transactions

    POST /sql {"statement": "BEGIN"}                      -> {"transaction": "<id>", ...}
    POST /sql {"statement": "INSERT ..."}  + Header  X-Transaction-Id: <id>
    POST /sql {"statement": "COMMIT"}      + Header  X-Transaction-Id: <id>   (or ROLLBACK)

The ID can instead be supplied as the `"transaction"` field in the JSON body.

- An open transaction locks the database for all other sessions (serializable, one writer). Other requests immediately
  receive 400 "locked"; they do not wait. `/tables`, `/stats`, `/merge` and `/checkpoint` are also locked.
- A transaction sees its own changes. Inactive transactions are rolled back after 30 seconds.
- Rollback: a snapshot is created before the first change to a table (copy-on-first-write, O(table)).
  `CREATE TABLE` is also rolled back.
- Log: the entire transaction is written as a `BEGIN ... COMMIT` group only at `COMMIT`. At startup, only complete
  groups are replayed; an incomplete remainder is discarded.
- A failed statement does not invalidate the transaction, but leaves no partial changes.
- Without `BEGIN`, each statement runs as its own transaction as before (autocommit).
- No savepoints or nested transactions.

## Stored procedures

A procedure is a named sequence of SQL statements with typed parameters. It is created, called and inspected using SQL,
from any client: SQL console, `POST /api/v1/sql`, Unix socket or embedded database.

    CREATE [OR REPLACE] PROCEDURE mark_paid (order_id INTEGER, who VARCHAR(40)) AS BEGIN
      UPDATE orders SET paid = TRUE, customer = :who WHERE id = :order_id;
      SELECT id, customer, paid FROM orders WHERE id = :order_id;
    END
    CALL mark_paid(1, 'ACME')
    SHOW PROCEDURES                -- name, parameters, statements, definition
    SHOW PROCEDURE mark_paid
    DROP PROCEDURE mark_paid

- **Parameters:** `:name` in the body. On invocation, each argument is checked against the parameter type (as with a
  value in `INSERT ... VALUES`) and substituted as a literal; text must be single-quoted, and `NULL` is always allowed.
  Expressions or statement fragments cannot be injected this way. Nothing is substituted inside 'text literals'.
  At creation, every parameter used is checked for a declaration.
- **Body:** `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE`, `DROP TABLE`, separated by `;`. No transaction
  control, calls to other procedures, variables or loops.
- **Result:** That of the last query in the body; `affected` counts changed rows across all statements.
- **All or nothing:** Outside a transaction, a `CALL` runs in its own transaction; if a statement fails, no changes
  remain. In an open transaction, the statements belong to it and `ROLLBACK` undoes them.
- **Caller's permissions:** `CALL` and `SHOW` require `execute` (`viewer` role or higher); creation, replacement and
  deletion require `manageProcedures` (`admin` role). Each statement in the body checks the caller's permissions and
  table grants: a procedure cannot give anyone more access than direct execution. A call's internal `BEGIN` does not
  require `transact`.
- **Durability:** Procedures appear in the statement log and at the beginning of the new log after a checkpoint. In
  backups and full replication snapshots they appear as the `hdb_procedures` table; this name is reserved and does not
  appear in the table list. A replication target receives created and deleted procedures in the change stream;
  `CALL` is blocked there like any write statement, while `SHOW` works.
- Creation and deletion are allowed only outside a transaction. Procedures belong to the tenant.

## WHERE pushdown

The WHERE condition is evaluated on the affected table before copying and joining when this does not change the result.
This saves copying and reduces the hash table's size.

- Conditions are pushed down for the first table and tables in an `INNER JOIN`.
- They are not pushed down for a `LEFT JOIN` table because its columns are filled with NULL
  (`WHERE o.id IS NULL` specifically finds unmatched rows). The condition applies after the join there.
- Unqualified columns are pushed down only if they occur in exactly one table. Ambiguity produces an error after the
  join, as before.
- With `FROM table alias` without a join, only matching rows are copied to the alias.
- The result is always the same as without pushdown. The `pushedDownFilters` counter in `SqlService` aids diagnosis.

## AND, OR and parentheses in WHERE

    SELECT k FROM w WHERE (n = 'a' OR n = 'b') AND v IS NOT NULL
    UPDATE w SET v = 0 WHERE n = 'a' AND k >= 3
    DELETE FROM w WHERE k = 1 OR k = 2

- Conditions `column op value` and `column IS [NOT] NULL`, combined with `AND`, `OR` and parentheses.
  `AND` binds more strongly than `OR`. `<>` is equivalent to `!=`. Keywords in text literals
  (`'x AND y'`) remain untouched.
- Applies to `SELECT`, `UPDATE` and `DELETE`. `NOT` is deliberately unavailable: with NULL values (three-valued logic),
  the complement of a match set would be incorrect. Without `NOT`, intersection (`AND`) and union (`OR`) of match sets
  are exact.
- Pushdown: the condition is split into its top-level `AND` parts. Each part whose columns all belong to exactly one
  eligible table (first table or `INNER JOIN`) is evaluated before the join, including an `OR` within one table.
  Parts spanning multiple tables and parts on the NULL-extended side of a `LEFT JOIN` apply after the join.

## IN, BETWEEN, LIKE

    SELECT k FROM p WHERE n LIKE 'a%' AND k IN (1, 4, 6)
    SELECT k FROM p WHERE v BETWEEN 2 AND 5 OR n NOT LIKE '%an%'

- `column [NOT] IN (value, ...)`, `column [NOT] BETWEEN a AND b` (inclusive bounds) and `column [NOT] LIKE 'pattern'`
  with `%` (any number of characters) and `_` (exactly one character); case matters and there is no escape character.
  `LIKE` applies only to text columns.
- Like all comparisons, these are never true when the column value is NULL, including `NOT IN`,
  `NOT BETWEEN` and `NOT LIKE`. `x NOT IN (1, NULL)` is never true; `x IN (1, NULL)` matches only 1.
- As with other comparisons, evaluation occurs once per DISTINCT dictionary value; the `AND` within `BETWEEN` belongs
  to the operator and is not interpreted as logical `AND`.
- Applies to `SELECT`, `UPDATE` and `DELETE`, and is pushed down before joins like any other condition.

## Multiple grouping columns

    SELECT region, product, COUNT(*), SUM(qty) FROM sales GROUP BY region, product ORDER BY region, product

- `GROUP BY column [, column ...]`, also with qualified names (`c.name`) after a join. Duplicates in the list count
  once. All grouping columns and aggregates are allowed in `SELECT` and `HAVING`, but grouping columns need not be selected.
- Implementation: for each grouping column, each DISTINCT value (main and delta) gets a dense ID; for each match,
  the IDs are combined into a key (mixed radix, `ulong`). No values are compared per row. An unrealistically large
  number of possible combinations produces an error.
- Without `ORDER BY`, groups are sorted lexicographically by key values, NULL first. NULL forms a separate value per column.

## DISTINCT

    SELECT DISTINCT region, product FROM sales ORDER BY region
    SELECT COUNT(DISTINCT customer), SUM(DISTINCT price) FROM sales

- `SELECT DISTINCT ...` removes duplicate result rows, including with `*`. Without aggregates, it runs as a `GROUP BY`
  over all selected columns (grouping by dictionary IDs). The result is therefore sorted by value, not insertion order.
  `ORDER BY` may name only selected columns (as in SQL).
- With aggregates or `GROUP BY`, completed result rows are deduplicated, followed by `ORDER BY` and `LIMIT`.
- `COUNT(DISTINCT x)`, `SUM(DISTINCT x)`, `AVG(DISTINCT x)`: NULL does not count; a value counts once per group, even
  if it appears in both main and delta stores. `MIN`/`MAX` with `DISTINCT` are equivalent to those without it.
  `COUNT(DISTINCT *)` is unavailable.

## Background delta merge

The merge locks the database only briefly. It runs in three phases (`domain/column.d`):

1. **Freeze** (briefly under lock): `beginMerge()` records main and the current delta rows.
2. **Build** (without lock, in a background thread): `MergeJob.run()` builds the sorted dictionary and newly packed
   codes. It reads only frozen data; main is never modified, only replaced, and frozen delta entries remain unchanged.
   Queries and changes continue normally.
3. **Switch** (briefly under lock): `finishMerge()` replaces main. Rows added to delta in the meantime get a new small
   delta. Row numbers do not change because frozen rows already follow main directly and delta has its own dictionary.

- Triggered automatically once a column has 1000 delta rows (after `INSERT`/`UPDATE`), and by `POST /merge`.
  This responds immediately with 202 (`STARTED` or `RUNNING`); `GET /merge` shows `running`, `completed` and
  `lastError`. At most one merge runs per column, and at most one merge thread overall.
- During a transaction, `POST /merge` and `/stats` remain locked like all other calls. An already running merge does
  not interfere with the transaction; rollback restores the table snapshot.
- No background merges start during log replay at startup; a synchronous merge runs afterwards.
- Limits: checkpoints, rollback snapshots and construction of temporary join tables still run under the lock.

### Background compaction

Removing deleted rows changes row numbers. This also runs in three phases (`domain/table.d`):

1. **Freeze** (under lock): `beginCompaction()` records row count `N`, the live row numbers and a snapshot of each
   column (main + delta). From then on, `markDeleted` records every deletion.
2. **Build** (without lock): `CompactionJob.run()` builds new columns with sorted dictionaries from the live rows.
3. **Switch** (under lock): `finishCompaction()` carries over what happened since freezing. Rows from `N` onward go
   into the new columns' delta, directly after the `L` live rows (new number `L + (old - N)`). Each recorded deletion
   is mapped to the new number: old rows by their rank among the live rows, new rows by the offset. An `UPDATE` is
   a deletion plus an insertion, so it is carried over correctly automatically.

- Automatic at 1000 deleted rows if they make up more than half the table (after `UPDATE`/`DELETE`), and explicitly
  via `POST /merge` for every table with deleted rows. A compacted table is not additionally merged column by column,
  because the build merges the delta too.
- During compaction, columns of that table are not merged, and an ongoing column merge prevents compaction from
  starting (it is skipped and retried in the next cycle).
- A rollback replaces the table with the snapshot; an already running job then works on the discarded table and has
  no effect. Row numbers are not retained across calls, so renumbering is invisible.
