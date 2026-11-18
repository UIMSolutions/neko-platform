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
`/api/v1/health`, `/auth/login`, `/auth/logout`, `/sql`, `/tables`, `/stats`, `/checkpoint` und `/merge`.

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
  (see [Replication](#replikation)), let it catch up, stop replication (making the target writable) and change the
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

## Benutzer und Rechte

Außer `GET /health`, `GET /api/v1/health` und den Anmeldeseiten verlangt jede Route eine Anmeldung.

Rechte werden über Rollen vergeben (RBAC), auf drei Ebenen:

| Ebene | Wer | Rechte |
|---|---|---|
| Server | Benutzer im Bereich `system` | `viewTenants`, `manageTenants`, `manageAccess` (Systembenutzer und -rollen), `viewLogs`, `manageLogs` |
| Mandant | Rolle eines Benutzers, gilt für alle Tabellen | `select`, `insert`, `update`, `delete`, `drop`, `create`, `transact`, `maintain`, `manageBackups`, `replicate`, `manageReplication`, `manageAccess`, `viewLogs`, `manageLogs`, `execute`, `manageProcedures` |
| Tabelle | Freigabe: Rolle für eine einzelne Tabelle | davon nur `select`, `insert`, `update`, `delete`, `drop` |

Vordefinierte Rollen, unveränderlich; bestehende Benutzer behalten damit ihre Rechte:

| Bereich | Rolle | Rechte |
|---|---|---|
| Mandant | `viewer` | `select`, `replicate`, `execute` |
| Mandant | `editor` | zusätzlich `insert`, `update`, `delete`, `transact` |
| Mandant | `admin` | alle Mandantenrechte |
| `system` | `viewer` | `viewTenants` |
| `system` | `admin` | alle Serverrechte |

Eigene Rollen legt man mit `manageAccess` unter `/admin/roles` oder per API an, je Mandant bzw. im Bereich `system`.
Ein Benutzer hat höchstens eine Rolle im Mandanten (oder keine) und beliebig viele Tabellenfreigaben unter
`/admin/users/<name>/grants`. Rechte addieren sich, es gibt keine Verbote. Ein Benutzer ohne Rolle sieht nur die
freigegebenen Tabellen.

    curl -X PUT localhost:8080/api/v1/roles/clerk -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"description":"Reads and adds rows","permissions":["select","insert"]}'
    curl localhost:8080/api/v1/users -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"name":"tina","password":"...","role":""}'
    curl -X PUT localhost:8080/api/v1/users/tina/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"grants":[{"table":"orders","role":"clerk"}]}'
    curl localhost:8080/api/v1/auth/me -H "Authorization: Bearer $TOKEN"   # aufgelöste Rechte, auch je Tabelle

- Tabellenrechte prüft der SQL-Kern an jeder Stelle, an der eine Anweisung eine Tabelle holt: bei Joins für jede
  beteiligte Tabelle, vor jeder Änderung. Eine verborgene Tabelle verhält sich wie eine fehlende (403 bzw. 404 mit
  derselben Meldung wie für unbekannte Tabellen), ihre Existenz wird nicht verraten.
- Tabellenlisten, Statistik, OData-`$metadata` und die Oberflächen zeigen nur Tabellen, auf denen der Benutzer ein Recht
  hat, und nur die Schaltflächen, die er nutzen darf.
- `create` und `transact` gelten nur im ganzen Mandanten: `BEGIN` sperrt alle Tabellen.
- Freigaben dürfen Tabellen nennen, die es noch nicht gibt, und gelten nach `DROP` für eine neu angelegte Tabelle
  gleichen Namens wieder.
- Rollen- und Freigabeänderungen wirken sofort, auch in laufenden Sitzungen. Eine Rolle lässt sich erst löschen,
  wenn sie niemand mehr verwendet.
- In jedem Bereich muss ein aktiver Benutzer `manageAccess` behalten; Änderungen, die das verhindern würden, werden
  abgelehnt. Dieses Recht kommt nur aus der Rolle im Mandanten, nie aus einer Tabellenfreigabe.
- Sicherungen (`manageBackups`) und der Replikationsstrom (`replicate`) enthalten alle Tabellen: diese Rechte deshalb
  nur Rollen geben, die ohnehin alles lesen dürfen.
- Eigene Rollen liegen in `ROLES_FILE` (Standard `data/hdb-roles.json`), Rollen und Freigaben der Benutzer in `USERS_FILE`.

Eine offene Transaktion kann nur ihr Besitzer verwenden.

### Befristete Rechte

Zusätzliche Rollen eines Benutzers (unter `/admin/users/<name>/grants` oder `PUT /api/v1/users/<name>/grants`) lassen
sich befristen. Ohne Tabelle gilt eine solche Rolle im ganzen Mandanten, im Bereich `system` auf dem Server, etwa
„admin bis Freitag 18 Uhr“:

    curl -X PUT localhost:8080/api/v1/users/vic/grants -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"grants":[{"table":"","role":"admin","until":"2026-11-13T17:00:00Z"},
                     {"table":"orders","role":"editor","from":"2026-11-10T08:00","until":"2026-11-10T18:00"}]}'

- `from` (einschließlich) und `until` (ausschließlich) sind optional und UTC; ohne Zeitzone gilt UTC. Gespeichert wird
  kanonisch (`2026-11-10T08:00:00Z`).
- Außerhalb des Zeitraums hat eine Freigabe keine Wirkung. Die Rechte werden bei jeder Anfrage neu aufgelöst: eine
  Freigabe beginnt und endet auf die Sekunde, auch in bereits offenen Sitzungen.
- Antworten nennen den Zustand (`active`, `scheduled`, `expired`). Abgelaufene Freigaben bleiben zur Nachvollziehbarkeit
  stehen, bis man sie entfernt („Remove expired grants“); neu anlegen lassen sich abgelaufene nicht.
- Befristete Rollen zählen nicht für die Regel, dass ein aktiver Benutzer `manageAccess` behalten muss: dafür zählt nur
  die dauerhafte Rolle.

### Erlaubte Netze

Administratoren eines Mandanten (`manageAccess`) legen unter `/admin/network` oder per API fest, von welchen
IP-Adressen und Netzen (IPv4/IPv6, CIDR) dessen Benutzer arbeiten dürfen. Eine leere Liste erlaubt alles.

    curl localhost:8080/api/v1/network -H "Authorization: Bearer $TOKEN"     # Liste und eigene Adresse
    curl -X PUT localhost:8080/api/v1/network -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"networks":["192.168.10.0/24","2001:db8::/32"]}'

- Geprüft wird bei der Anmeldung (nach dem Passwort; außerhalb: 403 mit Meldung) und bei jeder Anfrage. Ein Token, das von
  einer anderen Adresse kommt, gilt dort nicht; die Sitzung bleibt für erlaubte Adressen bestehen.
- Eine Liste, die die eigene Adresse ausschließt, wird abgelehnt: so sperrt sich niemand selbst aus. Haben sich die
  Administratoren eines Mandanten trotzdem ausgesperrt, setzen Systemadministratoren (`manageTenants`) die Liste auf der
  Mandantenseite oder per `PUT /api/v1/tenants/<name>/networks` zurück.
- Der Bereich `system` wird nicht eingeschränkt.
- Clients am Unix-Socket gelten als `127.0.0.1`. Replikationsziele brauchen ihre Adresse in der Liste der Quelle.
- Hinter einem Reverse-Proxy: `TRUSTED_PROXIES` (Adressen oder Netze, durch Komma getrennt) nennen. Nur von diesen
  Proxys gilt `X-Forwarded-For`, und zwar der letzte Eintrag, der kein vertrauter Proxy ist. Ohne die Variable zählt
  die Adresse der Verbindung; dann sieht der Server bei einem Proxy nur dessen Adresse.
- Die Listen stehen in `TENANTS_FILE` (Feld `networks`).

Erster Start: siehe Mandanten. Erzeugte Passwörter bitte unter `/admin/account` ändern; danach werden die Variablen
ignoriert. Administrator-Passwort eines Mandanten verloren: ein anderer Administrator des Mandanten setzt es zurück.
Gibt es keinen mehr, lässt sich der Mandant nur noch über `USERS_FILE` reparieren.

    TOKEN=$(curl -s localhost:8080/api/v1/auth/login -H 'Content-Type: application/json' \
      -d '{"user":"admin","password":"..."}' | jq -r .token)
    curl localhost:8080/sql -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"statement":"SELECT * FROM orders"}'

- Anmeldung: `/admin` nutzt ein Cookie (HttpOnly, SameSite=Strict), alle REST-Routen nur Bearer-Tokens. Tokens gelten
  12 Stunden, liegen nur als Hash im Speicher und enden bei Neustart, Passwortwechsel, Deaktivieren oder Löschen.
- Passwörter: mindestens 12 Zeichen, PBKDF2-HMAC-SHA256 mit 600 000 Runden. Nach 5 Fehlversuchen ist der Name 1 Minute
  gesperrt, auch wenn er nicht existiert. Dadurch kann ein Angreifer die Anmeldung eines Namens zeitweise blockieren.
- Benutzer aller Mandanten liegen in `USERS_FILE` (Standard `data/hdb-users.json`, Rechte 0600), nicht im Anweisungsprotokoll.
  Eine beschädigte Datei bricht den Start ab. Sicherungen müssen die Datei einschließen.
- Das Log enthält weiterhin alle Daten im Klartext; die Rechte gelten nur für den Zugriff über HTTP.
- Tokens, Cookies und Passwörter gehen im Klartext über HTTP: im Netz nur hinter TLS betreiben. Das Cookie erhält
  `Secure`, wenn der Proxy `X-Forwarded-Proto: https` setzt.

Durchgesetzt wird an einer Stelle: `TenantDatabases` wählt die Datenbank des angemeldeten Mandanten, und dort umschließt
`SecuredSqlUseCase` den Kern. Alle eingehenden Adapter sehen nur `TenantDatabases`.
`SecurityGate` setzt je Anfrage die Identität und lässt nur die öffentlichen Pfade ohne Anmeldung durch.

## Tabellenspeicher

    CREATE TABLE klein (id INTEGER, name VARCHAR) USING JSON

Beim Anlegen wählt man im Admin-Formular, per `USING` oder im Feld `storage` von `POST /api/v1/tables`, wo eine Tabelle
liegt. Ohne Angabe gilt `MEMORY`. Abfragen laufen immer im Hauptspeicher, der Unterschied betrifft nur die Dauerhaftigkeit.
Der Speicher lässt sich später nicht ändern; dafür Tabelle neu anlegen und Daten kopieren.

| Speicher | Repository | Dauerhaft durch | Schreiben kostet |
|---|---|---|---|
| `MEMORY` | `MemoryTableRepository` | Anweisungsprotokoll (siehe Persistenz) | eine Zeile im Log |
| `FILE` | `FileTableRepository` | `tables/file/<name>.tbl` (Text, tabulatorgetrennt) | ganze Datei neu |
| `JSON` | `JsonTableRepository` | `tables/json/<name>.json` | ganze Datei neu |
| `BINARY` | `BinaryTableRepository` | `tables/binary/<name>.bin` (kompakt, mit SHA-256) | ganze Datei neu |
| `BSON` | `BsonTableRepository` | `tables/bson/<name>.bson` (ein BSON-Dokument) | ganze Datei neu |

Die Pfade liegen im Verzeichnis des Mandanten (`TENANTS_DIR/<mandant>`, siehe Mandanten). `RoutingTableRepository` verteilt die Tabellen, Namen sind über alle Speicher
eindeutig. `GET /stats` und `GET /api/v1/stats` zeigen `storage`.

- `FILE`-, `JSON`-, `BINARY`- und `BSON`-Tabellen stehen nie im Anweisungsprotokoll: jede Tabelle hat genau eine dauerhafte Quelle.
- `BINARY`: little-endian, Zahlen bitgenau (int64, IEEE-754 double), Text als UTF-8 mit Längenangabe, exakte
  Dezimalzahlen als Text. Am Ende steht eine SHA-256-Prüfsumme; eine beschädigte Datei bricht den Start ab.
  Aufbau im Kommentar von `BinaryTableRepository`.
- `BSON`: `{format: "hdb-table", version: 1, name, columns: [{name, type}], rows: [[...], ...]}`. Ganzzahlen sind int64,
  `DOUBLE`/`REAL` double, `BOOLEAN` bool, alles andere string (auch `DECIMAL`, damit keine Stelle verloren geht).
  Lesbar etwa mit `bsondump tables/bson/<name>.bson`. Gelesen wird streng: unbekannte BSON-Typen, falsche Längen oder
  Werte, die nicht zum Spaltentyp passen, brechen den Start ab. BSON erlaubt höchstens 2 GB je Datei, MongoDB nimmt
  nur Dokumente bis 16 MB an.
- Geschrieben wird am Commit-Punkt, also nach jeder Anweisung oder beim `COMMIT`; `ROLLBACK` erreicht die Datei nie.
  Dateien werden per temporärer Datei, `fsync` und `rename` ersetzt, es liegt also der alte oder der neue Stand vor.
- Bei jeder Änderung wird die ganze Datei neu geschrieben. Für große oder oft geänderte Tabellen ist `MEMORY` die bessere Wahl.
- Eine Transaktion über mehrere Dateien oder über Datei und Log ist bei einem Absturz mitten im `COMMIT` nicht atomar:
  Dateien werden nacheinander geschrieben, das Log zuletzt.
- Eine beschädigte Datei, oder derselbe Tabellenname in zwei Speichern, bricht den Start ab.
- Die Dateien sind Klartext. Sicherungen des Servers müssen `TENANTS_DIR` einschließen.

## Sichern und Wiederherstellen

Nur für die Rolle `admin`, in der Administrationsoberfläche (`/admin/backups`), im Fiori-Frontend und per REST:

    curl -X POST localhost:8080/api/v1/backups -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' -d '{"label": "vor dem Update"}'
    curl localhost:8080/api/v1/backups -H "Authorization: Bearer $TOKEN"
    curl -o sicherung.hdbbak localhost:8080/api/v1/backups/<name>/content -H "Authorization: Bearer $TOKEN"
    curl -X POST --data-binary @sicherung.hdbbak localhost:8080/api/v1/backups/import \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/octet-stream'
    curl -X POST localhost:8080/api/v1/backups/<name>/restore -H "Authorization: Bearer $TOKEN"

- Sicherungen gehören zum Mandanten: Administratoren sehen und erzeugen nur Sicherungen ihres Mandanten, eine Wiederherstellung
  ersetzt nur dessen Tabellen, und jeder Mandant hat seinen eigenen Zeitplan.
- Eine Sicherung ist eine Datei (`*.hdbbak`, Rechte 0600) in `TENANTS_DIR/<mandant>/backups`. Sie enthält alle Tabellen
  aller Speicher mit Schema, Speicherart und exakten Werten und endet mit einer SHA-256-Prüfsumme. Sie ist nicht verschlüsselt.
- Sichern braucht einen ruhenden Stand: bei einer offenen Transaktion wird abgelehnt. Die Datenbank bleibt sonst benutzbar,
  ist aber während des Kopierens gesperrt. Eine Sicherung liegt vollständig im Speicher, auch beim Hoch- und Herunterladen.
- Wiederherstellen ersetzt alle Tabellen. Die Datei wird vorher vollständig geprüft, dann entsteht automatisch die
  Sicherheitskopie `before-restore`, mit der sich auch ein Erfolg rückgängig machen lässt. Schlägt das Ersetzen fehl, wird der alte
  Stand zurückgespielt. Bei einem Absturz mitten im Ersetzen kann ein Mischzustand bleiben: dann die Sicherheitskopie
  wiederherstellen. Sicherheitskopien werden nicht automatisch gelöscht.
- Benutzer gehören nicht zur Sicherung: eine Wiederherstellung sperrt niemanden aus und bringt keine alten Passwörter zurück.
  `USERS_FILE` muss getrennt gesichert werden.
- Hochgeladene Dateien gelten als nicht vertrauenswürdig. Die Prüfsumme erkennt Beschädigung, nicht Fälschung; Namen, Typen und
  Werte werden deshalb immer geprüft. Hochladen stellt noch nichts wieder her.
- `MAX_REQUEST_MB` (Standard 256) begrenzt Anfragen und damit die Größe beim Hochladen. Ohne Anmeldung gelten höchstens 64 KB.
- Sicherungen liegen auf demselben Datenträger wie die Daten: für den Schutz vor dessen Ausfall müssen sie zusätzlich an
  einen anderen Ort kopiert werden.

Zeitplan und Aufbewahrung sind standardmäßig aktiv: alle 24 Stunden eine Sicherung, 7 geplante und 5 Sicherheitskopien bleiben.
Einstellbar in beiden Oberflächen und per `GET|PUT /api/v1/backups/schedule`, gespeichert in `backups/schedule.json` des Mandanten.

    curl -X PUT localhost:8080/api/v1/backups/schedule -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"enabled": true, "intervalHours": 6, "keepScheduled": 28, "keepSafety": 5}'

- Die erste Sicherung entsteht kurz nach dem Start, sobald es Tabellen gibt. Ein Neustart setzt die Frist nicht zurück.
  `BACKUP_TICK_SECONDS` (Standard 60) legt fest, wie oft auf Fälligkeit geprüft wird.
- Die Aufbewahrung löscht nur die Arten `scheduled` und `safety`, die ältesten zuerst und erst nach einer erfolgreichen neuen
  Sicherung. Eigene und hochgeladene Sicherungen bleiben immer. Die Labels `scheduled` und `before-restore` sind deshalb reserviert.
  Weniger aufzubewahren wirkt sofort.
- Scheitert eine geplante Sicherung, etwa wegen einer offenen Transaktion, erscheint das in den Oberflächen und im Log; nach
  5 Minuten folgt der nächste Versuch.
- Die Aufbewahrung zählt, sie prüft keinen Inhalt: ein unbemerkt falscher Datenstand verdrängt nach `keepScheduled` Läufen alle
  älteren geplanten Stände. Wichtige Stände deshalb als eigene Sicherung anlegen.

## Replikation

Ein Mandant lässt sich auf einen anderen hdb-Server spiegeln: eine Quelle, beliebig viele Ziele, Änderungen fließen nur
von der Quelle zum Ziel. Das Ziel holt zuerst einen vollständigen Stand und danach jede bestätigte Änderung, für alle
Speicherarten (`MEMORY`, `FILE`, `JSON`). Ein Ziel kann selbst Quelle sein (A -> B -> C).

Einrichten auf dem Ziel, als Administrator des Ziel-Mandanten, unter `/admin/replication` oder per API. Auf der Quelle
genügt ein Benutzer mit der Rolle `viewer`:

    curl -X PUT localhost:8081/api/v1/replication/source -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"url":"https://primary:8080","tenant":"default","user":"replica","password":"...","intervalSeconds":2}'
    curl localhost:8081/api/v1/replication -H "Authorization: Bearer $TOKEN"              # Zustand
    curl -X POST localhost:8081/api/v1/replication/resync -H "Authorization: Bearer $TOKEN"  # vollständig neu holen
    curl -X DELETE localhost:8081/api/v1/replication/source -H "Authorization: Bearer $TOKEN"  # beenden

- Der erste Lauf ersetzt alle Tabellen des Ziel-Mandanten. Solange die Replikation läuft, nimmt das Ziel keine
  Schreibzugriffe an (403), auch kein `BEGIN` und keine Wiederherstellung; Lesen, Sicherungen und Statistik gehen.
  Nach dem Beenden behält das Ziel seinen Stand und ist wieder beschreibbar, etwa um es nach einem Ausfall der Quelle
  zu übernehmen.
- Die Quelle liefert `GET /api/v1/replication/snapshot` (Stand im Sicherungsformat, Position in `X-Hdb-Epoch` und
  `X-Hdb-Sequence`) und `GET /api/v1/replication/changes?epoch=&since=&max=`. Jede Änderung ist eine einzelne Anweisung
  oder eine ganze Transaktion; das Ziel spielt sie als Einheit ein. Zurückgerollte Transaktionen erscheinen nie.
- Der Änderungsstrom liegt nur im Speicher. Nach einem Neustart oder einer Wiederherstellung der Quelle beginnt eine neue
  Epoche, nach einem Neustart des Ziels ebenso: dann holt das Ziel einen vollständigen Stand. Das gilt auch, wenn es weiter
  zurückliegt, als die Quelle Änderungen aufbewahrt (`REPLICATION_RETAIN`, Standard 10000 je Mandant), oder wenn sich eine
  Änderung nicht einspielen lässt.
- Ausfälle der Quelle meldet das Ziel einmal im Log und in `lastError`, danach versucht es es im eingestellten Abstand
  (mindestens 5 Sekunden) weiter und holt auf. Abgelaufene Sitzungen erneuert es selbst.
- Das Passwort für die Quelle liegt im Klartext in `TENANTS_DIR/<mandant>/replication.json` (Rechte 0600), damit sich
  das Ziel neu anmelden kann. Die API gibt es nie aus; ein leeres Passwort beim Ändern behält es, aber nur für dieselbe
  Quelle und denselben Benutzer.
- Die Quelle wird mit den Rechten des Servers abgefragt. `REPLICATION_ALLOWED_HOSTS` (durch Komma getrennt) begrenzt
  die erlaubten Hosts; ohne die Variable dürfen Mandanten-Administratoren jede http(s)-Adresse eintragen.
- Zwischen Servern im Netz nur über TLS betreiben: Zugangsdaten und Daten gehen sonst im Klartext.
- Benutzer werden nicht repliziert, wie bei Sicherungen.

## Protokolle

Drei Protokolle, jedes mit eigenen Einstellungen, die Administratoren in `hdb-admin` (Seiten *Audit log*,
*Application log*, *Event log*, Knopf *Settings…*) oder über die REST-API ändern:

| Protokoll | Inhalt | Kategorien |
|---|---|---|
| `audit` | wer hat wann was getan, mit Adresse und Ergebnis; Fehlschläge mit Grund | `auth`, `users`, `roles`, `network`, `tenants`, `backups`, `replication`, `schema`, `data`, `maintenance`, `logs` |
| `event` | Betriebsereignisse | `server` (Start, Ende, Ersteinrichtung), `backups` (geplante Sicherungen), `replication` (Zustandswechsel, Fehler) |
| `application` | alles, was über `vibe.core.log` geht (auch aus vibe.d), mit dem meldenden Modul | – |

- **Bereiche:** jeder Mandant hat sein eigenes Audit- und Ereignisprotokoll mit eigenen Einstellungen und sieht nur
  diese. Der Bereich des Servers (`system`, im Einzelmandanten-Betrieb `default`) hat dazu das Anwendungsprotokoll und
  sieht die Einträge aller Mandanten (Filter `tenant`). Einträge zu unbekannten Mandanten (etwa eine Anmeldung bei
  einem erfundenen) landen im Bereich des Servers.
- **Rechte:** `viewLogs` zum Lesen, `manageLogs` zum Einstellen. Beide gehören zur Rolle `admin` im Mandanten und im
  Bereich `system` und lassen sich eigenen Rollen geben.
- **Einstellungen je Protokoll:** an/aus, Mindestschwere (`debug`, `info`, `warning`, `error`), Aufbewahrung in Tagen
  (1–3650), höchstens so viele Einträge (100–1 000 000) und die aufgezeichneten Kategorien. Voreinstellungen: Audit
  365 Tage / 50 000 ohne `data`, Ereignisse 90 Tage / 20 000, Anwendung 30 Tage / 20 000 ab `info`. Kürzere
  Aufbewahrung wirkt sofort, sonst räumt der Server stündlich auf.
- **Immer aufgezeichnet:** Änderungen an den Protokolleinstellungen (Kategorie `logs`), auch abgelehnte und auch bei
  abgeschaltetem Audit.
- **Audit-Schwere:** Erfolg `info`, Misserfolg `warning`; mit Mindestschwere `warning` bleiben nur Fehlschläge.
- **Nie im Protokoll:** Passwörter, Tokens, Werte aus Zeilen (`data` nennt nur Tabelle, Verb und Zeilenzahl), das
  Passwort einer Replikationsquelle. `SELECT`, `BEGIN`, `COMMIT` und `ROLLBACK` werden nicht aufgezeichnet,
  Änderungen in einer Transaktion beim Ausführen (auch wenn sie später zurückgerollt werden).
- **Ablage:** `LOG_DIR` (Standard `data/logs`) mit `audit.jsonl`, `event.jsonl`, `application.jsonl`, ein JSON-Objekt
  je Zeile, Rechte 0600; Einstellungen in `LOG_SETTINGS_FILE` (Standard `data/hdb-logs.json`). Eine beschädigte
  Einstellungsdatei bricht den Start ab; unlesbare Protokollzeilen werden übersprungen. Alle Einträge liegen auch im
  Speicher, gesucht wird dort.
- Ein Fehler beim Schreiben eines Eintrags hält keine Aktion auf.

REST (`kind` ist `audit`, `application` oder `event`):

    GET /api/v1/logs                        # Protokolle der Anmeldung mit Einstellungen und Kategorien
    GET /api/v1/logs/:kind?severity=warning&category=auth&actor=ann&text=login&tenant=acme&from=2026-11-08T00:00&until=...&limit=200&before=<id>
    GET /api/v1/logs/:kind/settings
    PUT /api/v1/logs/:kind/settings         # {"enabled", "minSeverity", "retentionDays", "maxEntries", "categories"}

Einträge kommen neueste zuerst mit `total` (alle Treffer); weiterblättern mit `before` = kleinste Id der Seite.

Aufbau: `domain/types/logentry.d` (Eintrag, Einstellungen, Kategorien), `application/services/logging.d`
(`LogService`: Filtern nach Einstellungen, Suche, Aufbewahrung), `application/services/audit.d` (Dekoratoren um
`IAccessUseCase`, `ITenantUseCase` und die Datenports: die Dienste selbst wissen nichts vom Audit),
`adapters/outbound/file_log_store.d` und `adapters/inbound/application_log.d` (vibe-Logger, der Zeilen aus allen
Threads puffert und im Hauptthread abgibt).

## Persistenz

Command-Log (Write-Ahead-Log) über den Port `IStatementLog`, Adapter `FileStatementLog`.
Jede erfolgreiche Änderung an `MEMORY`-Tabellen (`CREATE`, `DROP`, `INSERT`, `UPDATE`, `DELETE`) wird angehängt, beim Start spielt `recover()` das Log ein.
Nach 1000 Anweisungen oder per `POST /checkpoint` wird das Log kompakt neu geschrieben.
Datei: `TENANTS_DIR/<mandant>/hdb.log`, je Mandant eine (siehe Mandanten). `DATA_FILE` nennt nur noch den bisherigen Ort für die Umstellung.

## Spaltenspeicher: Dictionary + Delta-Merge

Jede Spalte (`domain/column.d`) besteht aus einem sortierten Main-Store (Dictionary + Codes) und einem
Delta-Store (unsortiertes Dictionary + Codes). `INSERT` landet im Delta. Der Delta-Merge baut das sortierte
Dictionary neu auf und schreibt alle Codes um; er läuft im Hintergrund (siehe unten), automatisch ab 1000
Delta-Zeilen, per `POST /merge` und einmal synchron nach dem Start. `WHERE` wird nur pro DISTINCT-Wert ausgewertet, danach werden Codes
gescannt. `GET /stats` zeigt Zeilen und DISTINCT-Werte je Spalte (Main/Delta).

## GROUP BY

    SELECT customer, COUNT(*), SUM(amount) FROM orders WHERE amount >= 10 GROUP BY customer

Erlaubt sind die Gruppierungsspalte, `COUNT(*)` und `SUM(x)`. Die Gruppe wird je DISTINCT-Schlüssel des
Dictionarys (Main und Delta) bestimmt, nicht je Zeile. Ergebnis sortiert nach Gruppenwert.

## Bitpacking

Die Main-Codes liegen in `domain/packed_vector.d`: jeder Code belegt nur `ceil(log2(distinct))` Bits statt 32.
`GET /stats` zeigt `mainBits` und `mainCodeBytes` je Spalte.

## ORDER BY und weitere Aggregate

    SELECT n, MIN(q), MAX(q), AVG(w) FROM p WHERE q >= 1 GROUP BY n ORDER BY AVG(w) DESC, n
    SELECT n FROM p ORDER BY q DESC

- Aggregate: `COUNT(*)`, `SUM(x)`, `AVG(x)` (nur numerisch), `MIN(x)`, `MAX(x)` (auch Text); auch ohne `GROUP BY`.
- `ORDER BY` mit mehreren Schlüsseln, `ASC`/`DESC`. Ohne Aggregation darf nach jeder Tabellenspalte sortiert
  werden, auch nach nicht ausgewählten. Mit Aggregation: Ergebnisspalte, Ausdruck wie im SELECT oder Position (1-basiert).
- Die Sortierung ist stabil. Ohne `ORDER BY` sind Gruppen nach dem Gruppenwert sortiert.
- Ergebnisspalten heißen jetzt `COUNT` und z.B. `SUM(amount)`.
- Aggregate ignorieren NULL; ohne Werte liefern `SUM`/`AVG`/`MIN`/`MAX` NULL, `COUNT` liefert 0.

## HAVING, LIMIT, OFFSET

    SELECT g, SUM(v) FROM h GROUP BY g HAVING COUNT(*) >= 2 ORDER BY SUM(v) DESC LIMIT 10 OFFSET 20

- `HAVING ausdruck op wert`: Ausdruck ist ein Aggregat oder die Gruppierungsspalte; er muss nicht im `SELECT` stehen.
- `LIMIT n [OFFSET m]` wirkt nach `ORDER BY`. `OFFSET` gibt es nur zusammen mit `LIMIT`.
- Reihenfolge: WHERE, GROUP BY, HAVING, ORDER BY, LIMIT.

## UPDATE und DELETE

    UPDATE orders SET amount = 120.5, customer = 'ACME' WHERE id = 7
    DELETE FROM orders WHERE amount < 10

- `DELETE` markiert Zeilen in einem Löschvektor; alle Abfragen überspringen sie.
- `UPDATE` ist insert-only: die alte Zeilenversion wird gelöscht, die neue landet im Delta (am Ende der Tabelle,
  daher ändert sich die Reihenfolge ohne `ORDER BY`).
- Gelöschte Zeilen werden beim Delta-Merge (`POST /merge`, nach dem Start) physisch entfernt, automatisch ab 1000 gelöschten
  Zeilen, wenn sie mehr als die Hälfte der Tabelle ausmachen. Beim Checkpoint werden sie nicht ins Log geschrieben.
- Beide Anweisungen werden ins Log geschrieben und beim Start deterministisch wieder eingespielt.
- `GET /stats` zeigt `rows` (lebende Zeilen) und `deletedRows`.

## DROP TABLE

    DROP TABLE orders

Wird geloggt und beim Start wiederholt. In einer Transaktion stellt `ROLLBACK` die Tabelle samt Daten wieder her.

## JOIN

    SELECT c.name, SUM(o.amt) FROM customers c JOIN orders o ON c.id = o.cid
    WHERE o.amt >= 2 GROUP BY c.name ORDER BY SUM(o.amt) DESC

- `[INNER] JOIN tabelle [alias] ON a = b`, auch mehrere hintereinander (links-tief). Umgesetzt als Hash-Join.
- Das Join-Ergebnis ist eine temporäre Spaltentabelle mit Spalten `alias.spalte`; WHERE, GROUP BY, HAVING,
  ORDER BY und Aggregate laufen darauf unverändert. Unqualifizierte Namen gehen, wenn sie eindeutig sind.
- Ein Alias auf einer einzelnen Tabelle (`FROM orders o`) erlaubt `o.spalte`.
- Nur Gleichheits-Joins (INNER und LEFT). Self-Joins brauchen zwei verschiedene Aliase.
- Beide Seiten werden für den Join kopiert (Speicher O(Zeilen)), allerdings nur die Zeilen, die nach dem
  WHERE-Pushdown (siehe unten) übrig bleiben.

## NULL und LEFT JOIN

    SELECT c.name, COUNT(o.id) FROM customers c LEFT JOIN orders o ON c.id = o.cid GROUP BY c.name
    SELECT c.name FROM customers c LEFT JOIN orders o ON c.id = o.cid WHERE o.id IS NULL

- `LEFT [OUTER] JOIN`: linke Zeilen ohne Treffer bleiben erhalten, die rechten Spalten sind NULL.
- NULL-Literal in `INSERT` und `UPDATE ... SET x = NULL`; `WHERE x IS [NOT] NULL`.
- Vergleiche mit NULL sind nie wahr (`x = NULL` trifft nichts, dafür gibt es `IS NULL`). NULL passt in keinem Join auf NULL.
- `COUNT(spalte)` zählt nur Nicht-NULL-Werte, `COUNT(*)` alle Zeilen. NULL bildet in `GROUP BY` eine eigene Gruppe.
- `ORDER BY`: NULL sortiert zuerst (bei `DESC` zuletzt). Im JSON erscheint NULL als `null`, im Log als `NULL`.

## Transaktionen

    POST /sql {"statement": "BEGIN"}                      -> {"transaction": "<id>", ...}
    POST /sql {"statement": "INSERT ..."}  + Header  X-Transaction-Id: <id>
    POST /sql {"statement": "COMMIT"}      + Header  X-Transaction-Id: <id>   (oder ROLLBACK)

Die ID kann statt im Header auch als Feld `"transaction"` im JSON-Body stehen.

- Eine offene Transaktion sperrt die Datenbank für alle anderen Sitzungen (serialisierbar, ein Schreiber).
  Andere Anfragen bekommen sofort 400 "gesperrt"; es wird nicht gewartet. Auch `/tables`, `/stats`, `/merge`
  und `/checkpoint` sind währenddessen gesperrt.
- Eigene Änderungen sind in der Transaktion sichtbar. Ohne Aktivität werden Transaktionen nach 30 s zurückgerollt.
- Rollback: vor der ersten Änderung einer Tabelle wird ein Snapshot angelegt (Copy-on-first-write, O(Tabelle)).
  Auch `CREATE TABLE` wird zurückgerollt.
- Log: erst beim `COMMIT` wird die ganze Transaktion als Gruppe `BEGIN ... COMMIT` geschrieben. Beim Start werden
  nur vollständige Gruppen eingespielt; ein unvollständiger Rest wird verworfen.
- Ein fehlerhaftes Statement macht die Transaktion nicht ungültig, hinterlässt aber keine Teiländerung.
- Ohne `BEGIN` läuft jede Anweisung wie bisher als eigene Transaktion (Autocommit).
- Keine Savepoints und keine verschachtelten Transaktionen.

## Gespeicherte Prozeduren

Eine Prozedur ist eine benannte Folge von SQL-Anweisungen mit typisierten Parametern. Angelegt, aufgerufen und
angesehen wird sie mit SQL, also aus jedem Client: SQL-Konsole, `POST /api/v1/sql`, Unix-Socket, eingebettete Datenbank.

    CREATE [OR REPLACE] PROCEDURE mark_paid (order_id INTEGER, who VARCHAR(40)) AS BEGIN
      UPDATE orders SET paid = TRUE, customer = :who WHERE id = :order_id;
      SELECT id, customer, paid FROM orders WHERE id = :order_id;
    END
    CALL mark_paid(1, 'ACME')
    SHOW PROCEDURES                -- name, parameters, statements, definition
    SHOW PROCEDURE mark_paid
    DROP PROCEDURE mark_paid

- **Parameter:** `:name` im Rumpf. Beim Aufruf wird jedes Argument gegen den Typ des Parameters geprüft (wie ein Wert in
  `INSERT ... VALUES`) und als Literal eingesetzt; Text muss in Hochkommata stehen, `NULL` geht immer. Ausdrücke oder
  Anweisungsteile lassen sich so nicht einschleusen. In 'Textliteralen' wird nichts ersetzt. Schon beim Anlegen wird
  geprüft, dass jeder verwendete Parameter deklariert ist.
- **Rumpf:** `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE`, `DROP TABLE`, getrennt durch `;`. Keine
  Transaktionssteuerung, keine Aufrufe anderer Prozeduren, keine Variablen oder Schleifen.
- **Ergebnis:** das der letzten Abfrage im Rumpf; `affected` zählt die geänderten Zeilen aller Anweisungen.
- **Alles oder nichts:** Außerhalb einer Transaktion läuft ein `CALL` in einer eigenen; scheitert eine Anweisung, ist keine
  Änderung geblieben. In einer offenen Transaktion gehören die Anweisungen zu ihr, `ROLLBACK` nimmt sie zurück.
- **Rechte des Aufrufers:** `CALL` und `SHOW` brauchen `execute` (Rolle `viewer` und höher), Anlegen, Ersetzen und Löschen
  `manageProcedures` (Rolle `admin`). Jede Anweisung im Rumpf prüft die Rechte und Tabellenfreigaben des Aufrufers: über
  eine Prozedur kann niemand mehr als direkt. Das interne `BEGIN` eines Aufrufs braucht kein `transact`.
- **Dauerhaft:** Prozeduren stehen im Anweisungsprotokoll und nach einem Checkpoint am Anfang des neuen. In Sicherungen
  und im vollständigen Stand der Replikation stehen sie als Tabelle `hdb_procedures`; der Name ist dafür reserviert und
  erscheint nicht in der Tabellenliste. Ein Replikationsziel erhält neue und gelöschte Prozeduren mit dem Änderungsstrom;
  dort ist `CALL` wie jede schreibende Anweisung gesperrt, `SHOW` geht.
- Anlegen und Löschen nur außerhalb einer Transaktion. Die Prozeduren gehören zum Mandanten.

## WHERE-Pushdown

Die WHERE-Bedingung wird vor dem Kopieren und Joinen auf der betroffenen Tabelle ausgewertet, wenn das das
Ergebnis nicht verändert. Das spart Kopierarbeit und verkleinert die Hash-Tabelle.

- Vorgezogen wird bei der ersten Tabelle und bei Tabellen eines `INNER JOIN`.
- Nicht vorgezogen wird bei einer `LEFT JOIN`-Tabelle, weil deren Spalten mit NULL aufgefüllt werden
  (`WHERE o.id IS NULL` findet gerade die Zeilen ohne Treffer). Dort gilt die Bedingung nach dem Join.
- Unqualifizierte Spalten werden nur vorgezogen, wenn sie in genau einer Tabelle vorkommen. Bei Mehrdeutigkeit
  gibt es wie bisher einen Fehler nach dem Join.
- Bei `FROM tabelle alias` ohne Join werden nur die Treffer in die Alias-Kopie übernommen.
- Das Ergebnis ist immer dasselbe wie ohne Pushdown. Der Zähler `pushedDownFilters` im `SqlService` dient der Diagnose.

## AND, OR und Klammern in WHERE

    SELECT k FROM w WHERE (n = 'a' OR n = 'b') AND v IS NOT NULL
    UPDATE w SET v = 0 WHERE n = 'a' AND k >= 3
    DELETE FROM w WHERE k = 1 OR k = 2

- Bedingungen `spalte op wert` und `spalte IS [NOT] NULL`, verknüpft mit `AND`, `OR` und Klammern.
  `AND` bindet stärker als `OR`. `<>` ist gleichbedeutend mit `!=`. Schlüsselwörter in Textliteralen
  (`'x AND y'`) bleiben unangetastet.
- Gilt für `SELECT`, `UPDATE` und `DELETE`. `NOT` gibt es bewusst nicht: Mit NULL-Werten (Dreiwertlogik) wäre
  das Komplement einer Treffermenge falsch. Ohne `NOT` sind Schnitt (`AND`) und Vereinigung (`OR`) der
  Treffermengen exakt.
- Pushdown: Die Bedingung wird in ihre obersten `AND`-Teile zerlegt. Jeder Teil, dessen Spalten alle zu genau
  einer vorziehbaren Tabelle gehören (erste Tabelle oder `INNER JOIN`), wird vor dem Join ausgewertet, auch ein
  `OR` innerhalb einer Tabelle. Teile über mehrere Tabellen und Teile auf der NULL-ergänzten Seite eines
  `LEFT JOIN` gelten nach dem Join.

## IN, BETWEEN, LIKE

    SELECT k FROM p WHERE n LIKE 'a%' AND k IN (1, 4, 6)
    SELECT k FROM p WHERE v BETWEEN 2 AND 5 OR n NOT LIKE '%an%'

- `spalte [NOT] IN (wert, ...)`, `spalte [NOT] BETWEEN a AND b` (Grenzen inklusive) und `spalte [NOT] LIKE 'muster'`
  mit `%` (beliebig viele Zeichen) und `_` (genau ein Zeichen); Groß-/Kleinschreibung zählt, ein Escape-Zeichen gibt
  es nicht. `LIKE` gilt nur für Textspalten.
- Wie alle Vergleiche sind auch diese nie wahr, wenn der Spaltenwert NULL ist, also auch `NOT IN`,
  `NOT BETWEEN` und `NOT LIKE`. `x NOT IN (1, NULL)` ist nie wahr, `x IN (1, NULL)` trifft nur die 1.
- Die Prüfung läuft wie die übrigen Vergleiche einmal pro DISTINCT-Wert des Dictionarys; das `AND` innerhalb von
  `BETWEEN` gehört zum Operator und wird nicht als logisches `AND` gelesen.
- Gilt in `SELECT`, `UPDATE` und `DELETE` und wird wie jede andere Bedingung vor einem Join vorgezogen.

## Mehrere Gruppierungsspalten

    SELECT region, product, COUNT(*), SUM(qty) FROM sales GROUP BY region, product ORDER BY region, product

- `GROUP BY spalte [, spalte ...]`, auch mit qualifizierten Namen (`c.name`) nach einem Join. Duplikate in der Liste
  zählen einmal. Im `SELECT` und in `HAVING` sind alle Gruppierungsspalten und Aggregate erlaubt, die
  Gruppierungsspalten müssen aber nicht ausgewählt werden.
- Umsetzung: Je Gruppierungsspalte bekommt jeder DISTINCT-Wert (Main und Delta) eine dichte Id; je Treffer werden die
  Ids zu einem Schlüssel kombiniert (gemischte Basis, `ulong`). Es werden also keine Werte pro Zeile verglichen.
  Bei einer unrealistisch großen Zahl möglicher Kombinationen gibt es einen Fehler.
- Ohne `ORDER BY` sind die Gruppen lexikographisch nach den Schlüsselwerten sortiert, NULL zuerst. NULL bildet
  je Spalte einen eigenen Wert.

## DISTINCT

    SELECT DISTINCT region, product FROM sales ORDER BY region
    SELECT COUNT(DISTINCT customer), SUM(DISTINCT price) FROM sales

- `SELECT DISTINCT ...` entfernt doppelte Ergebniszeilen, auch mit `*`. Ohne Aggregate wird das als `GROUP BY` über
  alle ausgewählten Spalten ausgeführt (Gruppierung über die Dictionary-Ids). Das Ergebnis ist daher nach den
  Werten sortiert, nicht in Einfügereihenfolge. `ORDER BY` darf nur ausgewählte Spalten nennen (wie in SQL).
- Mit Aggregaten oder `GROUP BY` werden die fertigen Ergebniszeilen dedupliziert, danach folgen `ORDER BY` und `LIMIT`.
- `COUNT(DISTINCT x)`, `SUM(DISTINCT x)`, `AVG(DISTINCT x)`: NULL zählt nicht, ein Wert zählt je Gruppe einmal, auch wenn
  er im Main- und im Delta-Store vorkommt. `MIN`/`MAX` mit `DISTINCT` sind gleichbedeutend mit ohne.
  `COUNT(DISTINCT *)` gibt es nicht.

## Delta-Merge im Hintergrund

Der Merge sperrt die Datenbank nur noch kurz. Er läuft in drei Phasen (`domain/column.d`):

1. **Einfrieren** (unter der Sperre, kurz): `beginMerge()` merkt sich Main und die aktuellen Delta-Zeilen.
2. **Aufbau** (ohne Sperre, in einem Hintergrund-Thread): `MergeJob.run()` baut das sortierte Dictionary und die neu
   gepackten Codes. Er liest nur die eingefrorenen Daten; das Main wird nie verändert, nur ersetzt, und eingefrorene
   Delta-Einträge bleiben unverändert. Abfragen und Änderungen laufen währenddessen normal weiter.
3. **Umschalten** (unter der Sperre, kurz): `finishMerge()` ersetzt Main. Zeilen, die in der Zwischenzeit ins Delta kamen,
   bekommen ein neues kleines Delta. Zeilennummern ändern sich nicht, weil die eingefrorenen Zeilen schon direkt hinter
   dem Main stehen und das Delta ein eigenes Dictionary hat.

- Ausgelöst wird er automatisch, sobald eine Spalte 1000 Delta-Zeilen hat (nach `INSERT`/`UPDATE`), und per
  `POST /merge`. Das antwortet sofort mit 202 (`STARTED` oder `RUNNING`); `GET /merge` zeigt `running`,
  `completed` und `lastError`. Pro Spalte läuft höchstens ein Merge, insgesamt höchstens ein Merge-Thread.
- Während einer Transaktion bleiben `POST /merge` und `/stats` gesperrt wie alle anderen Aufrufe. Ein schon laufender
  Merge stört die Transaktion nicht; ein Rollback stellt den Snapshot der Tabelle wieder her.
- Beim Einspielen des Logs beim Start werden keine Hintergrund-Merges gestartet; danach läuft ein synchroner Merge.
- Grenzen: Checkpoint, Rollback-Snapshots und der Aufbau temporärer Join-Tabellen laufen weiterhin unter der Sperre.

### Kompaktierung im Hintergrund

Gelöschte Zeilen zu entfernen ändert die Zeilennummern. Auch das läuft in drei Phasen (`domain/table.d`):

1. **Einfrieren** (unter der Sperre): `beginCompaction()` merkt sich Zeilenzahl `N`, die Nummern der lebenden Zeilen
   und je Spalte eine Momentaufnahme (Main + Delta). Ab jetzt protokolliert `markDeleted` jede Löschung.
2. **Aufbau** (ohne Sperre): `CompactionJob.run()` baut aus den lebenden Zeilen neue Spalten mit sortiertem Dictionary.
3. **Umschalten** (unter der Sperre): `finishCompaction()` überträgt, was seit dem Einfrieren geschah.
   Zeilen ab `N` kommen ins Delta der neuen Spalten und stehen direkt hinter den `L` lebenden Zeilen (neue Nummer
   `L + (alt - N)`). Jede protokollierte Löschung wird auf die neue Nummer abgebildet: alte Zeilen über ihren Rang
   unter den lebenden Zeilen, neue Zeilen über die Verschiebung. Ein `UPDATE` ist Löschen plus Einfügen und
   wird damit automatisch richtig übertragen.

- Automatisch ab 1000 gelöschten Zeilen, wenn sie mehr als die Hälfte der Tabelle sind (nach `UPDATE`/`DELETE`), und
  ausdrücklich per `POST /merge` für jede Tabelle mit gelöschten Zeilen. Eine kompaktierte Tabelle wird nicht zusätzlich
  spaltenweise gemergt, denn der Aufbau mergt das Delta mit.
- Während der Kompaktierung werden Spalten dieser Tabelle nicht gemergt, und eine laufende Spalten-Merge verhindert
  den Start der Kompaktierung (sie wird übersprungen und beim nächsten Zyklus nachgeholt).
- Ein Rollback ersetzt die Tabelle durch den Snapshot; ein schon laufender Job arbeitet dann auf der verworfenen Tabelle
  und ist wirkungslos. Zeilennummern werden nirgends über Aufrufe hinweg gehalten, die Umnummerierung ist daher unsichtbar.
