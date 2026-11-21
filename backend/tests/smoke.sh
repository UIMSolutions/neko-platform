#!/usr/bin/env bash
# End-to-end smoke test of two platform instances (open → secret).
#
#   dub build --config=open && dub build --config=secret
#   backend/tests/smoke.sh
#
# Uses throw-away ports and data directories; needs curl and python3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${BIN:-$ROOT/backend/build}" # BIN=build for the binaries of a root `dub build`
WORK="$(mktemp -d)"
OPEN_PORT=${OPEN_PORT:-18180}
SECRET_PORT=${SECRET_PORT:-18183}
SOCKET="$WORK/secret.sock"
PIDS=()

cleanup() {
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$WORK"
}
trap cleanup EXIT

failures=0
check() { # check <description> <expected> <actual>
  if [[ "$3" == *"$2"* ]]; then
    echo "  ok    $1"
  else
    echo "  FAIL  $1: expected '$2', got '$3'"
    failures=$((failures + 1))
  fi
}
json() { python3 -c "import sys,json; print(json.load(sys.stdin)$1)"; }

cd "$WORK"
export NEKO_DATA_DIR="$WORK/data" NEKO_FRONTEND_DIR=none NEKO_LOG_LEVEL=warn

echo "CLI (file storage, no server)"
out=$("$BIN/platform-open" services register --name=self --description="this instance" \
  --url="http://127.0.0.1:$OPEN_PORT" --activate)
check "register via CLI" "Status          active" "$out"
check "classification defaults to the platform domain" "Classification  open" "$out"
check "list shows the service" "self" "$("$BIN/platform-open" services list)"
set +e
"$BIN/platform-open" services register --name=vault --classification=secret >/dev/null 2>"$WORK/err"
code=$?
set -e
check "open platform refuses secret services (exit code)" "1" "$code"
check "… with a policy message" "cannot host secret" "$(cat "$WORK/err")"

echo "HTTP (open on :$OPEN_PORT, secret on unix socket)"
NEKO_PORT=$OPEN_PORT NEKO_ADMIN_PASSWORD=smoke-admin-pw NEKO_TRUSTED_PROXIES=127.0.0.1 "$BIN/platform-open" >"$WORK/open.log" 2>&1 & PIDS+=($!)
NEKO_TRANSPORT=unix NEKO_UNIX_SOCKET="$SOCKET" NEKO_ENFORCE_SCOPES=true \
  "$BIN/platform-secret" >"$WORK/secret.log" 2>&1 & PIDS+=($!)
for _ in $(seq 50); do
  [[ -S "$SOCKET" ]] && curl -s "http://127.0.0.1:$OPEN_PORT/health" >/dev/null && break
  sleep 0.1
done

O="http://127.0.0.1:$OPEN_PORT"
S=(--unix-socket "$SOCKET")
J=(-H 'Content-Type: application/json')

check "health (tcp)" "ok open" "$(curl -s $O/health)"
check "health (unix socket)" "ok secret" "$(curl -s "${S[@]}" http://localhost/health)"
check "server sees the CLI's service" '"name":"self"' "$(curl -s $O/rest/v1/services)"

id=$(curl -s $O/rest/v1/services | json '[0]["id"]')
check "health check of itself" '"health":"up"' "$(curl -s -X POST $O/rest/v1/services/$id/check)"

tid=$(curl -s "${J[@]}" -H 'X-User-Id: jane' \
  -d '{"name":"feed","targetDomain":"secret","payload":"{\"k\":1}"}' $O/rest/v1/transfers/export | json '["id"]')
curl -s $O/rest/v1/transfers/$tid/package >"$WORK/pkg.json"
check "transfer document is sealed" '"checksum"' "$(cat "$WORK/pkg.json")"

check "secret refuses writes without Admin scope" "403" \
  "$(curl -s -o /dev/null -w '%{http_code}' "${S[@]}" "${J[@]}" --data @"$WORK/pkg.json" http://localhost/rest/v1/transfers/import)"

# Unsigned test token with an Admin scope (the approuter validates real tokens).
payload=$(printf '{"user_name":"officer","scope":["neko-platform!t1.Admin"]}' | base64 -w0 | tr '+/' '-_' | tr -d '=')
A=(-H "Authorization: Bearer eyJhbGciOiJub25lIn0.$payload.x")

check "import with Admin scope" '"status":"imported"' \
  "$(curl -s "${S[@]}" "${J[@]}" "${A[@]}" --data @"$WORK/pkg.json" http://localhost/rest/v1/transfers/import)"
check "replay is refused" "409" \
  "$(curl -s -o /dev/null -w '%{http_code}' "${S[@]}" "${J[@]}" "${A[@]}" --data @"$WORK/pkg.json" http://localhost/rest/v1/transfers/import)"
sed 's/{\\"k\\":1}/{\\"k\\":2}/' "$WORK/pkg.json" | python3 -c 'import sys,json; d=json.load(sys.stdin); d["id"]="tampered"; print(json.dumps(d))' >"$WORK/bad.json"
check "tampered package is refused" "422" \
  "$(curl -s -o /dev/null -w '%{http_code}' "${S[@]}" "${J[@]}" "${A[@]}" --data @"$WORK/bad.json" http://localhost/rest/v1/transfers/import)"
check "export from secret is refused" "403" \
  "$(curl -s -o /dev/null -w '%{http_code}' "${S[@]}" "${J[@]}" "${A[@]}" -d '{"name":"x","targetDomain":"open","payload":"x"}' http://localhost/rest/v1/transfers/export)"

echo "OData"
check "\$metadata" "<Singleton Name=\"Overview\"" "$(curl -s "$O/odata/v4/platform/\$metadata")"
check "HEAD service root (UI5 token probe)" "200" "$(curl -s -o /dev/null -w '%{http_code}' -I $O/odata/v4/platform/)"
check "rejected package is audited" '"RejectedTransfers":1' "$(curl -s "${S[@]}" http://localhost/odata/v4/platform/Overview)"
check "\$filter/\$count" '"@odata.count":1' \
  "$(curl -s "${S[@]}" "http://localhost/odata/v4/platform/Transfers?\$count=true&\$filter=(Status%20eq%20'imported'%20and%20contains(Name,'fe'))")"
check "action SuspendService" '"Status":"suspended"' \
  "$(curl -s "${J[@]}" -d "{\"ID\":\"$id\"}" $O/odata/v4/platform/SuspendService)"
check "DELETE needs a retired service" "409" \
  "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$O/odata/v4/platform/Services('$id')")"
check "status page needs sign-in" "302" "$(curl -s -o /dev/null -w '%{http_code}' $O/status)"
check "wrong password refused" "401" \
  "$(curl -s -o /dev/null -w '%{http_code}' -d 'user=admin&password=wrong-password' $O/login)"
check "sign-in" "303" \
  "$(curl -s -o /dev/null -w '%{http_code}' -c "$WORK/cookies" -d 'user=admin&password=smoke-admin-pw' $O/login)"
check "status page" "self" "$(curl -s -b "$WORK/cookies" $O/status)"
check "user management" "admin" "$(curl -s -b "$WORK/cookies" $O/users)"
check "roles page lists the built-in roles" "auditor" "$(curl -s -b "$WORK/cookies" $O/roles)"
check "embedded Tabler CSS" "200" "$(curl -s -o /dev/null -w '%{http_code}' $O/ui/tabler-1.7.3.min.css)"
check "embedded Tabler JS" "200" "$(curl -s -o /dev/null -w '%{http_code}' $O/ui/tabler-1.7.3.min.js)"

echo "Roles and access rights"
csrf=$(curl -s -b "$WORK/cookies" $O/account | python3 -c \
  "import sys,re; print(re.search(r'X-CSRF-Token(?:&quot;|\")\s*:\s*(?:&quot;|\")([^&\"]+)', sys.stdin.read()).group(1))")
post() { # post <cookies> <path> <form data…>
  local jar=$1 path=$2; shift 2
  curl -s -o /dev/null -w '%{http_code}' -b "$jar" -H "Origin: $O" -H "HX-Request: true" \
    -H "X-CSRF-Token: $csrf" "$@" "$O$path"
}
check "POST without CSRF token refused" "403" \
  "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/cookies" -H "Origin: $O" -d 'name=ops' $O/roles)"
check "create role 'ops'" "200" \
  "$(post "$WORK/cookies" /roles -d 'name=ops&label=Operators&rights=status.read&rights=users.read')"
check "create user 'vic' with role ops" "200" \
  "$(post "$WORK/cookies" /users -d 'userName=vic&roles=ops&active=on&password=vic-password-1&confirm=vic-password-1')"
check "role in use cannot be removed" "in use" \
  "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" -H "X-CSRF-Token: $csrf" -D - \
    -X POST $O/roles/ops/delete | grep -i '^HX-Trigger' | sed 's/still assigned/in use/')"
check "vic signs in" "303" \
  "$(curl -s -o /dev/null -w '%{http_code}' -c "$WORK/vic" -d 'user=vic&password=vic-password-1' $O/login)"
check "vic lands on the first page with rights" "/status" \
  "$(curl -s -o /dev/null -w '%{redirect_url}' -b "$WORK/vic" $O/start)"
check "vic sees the status page" "200" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/vic" $O/status)"
check "… without events (no events.read)" "0" "$(curl -s -b "$WORK/vic" $O/status | grep -c 'Recent events' || true)"
check "vic lists users (users.read)" "200" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/vic" $O/users)"
check "vic cannot open the user dialog (no users.manage)" "403" \
  "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/vic" $O/users/new)"
check "vic cannot see roles (no roles.read)" "403" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/vic" $O/roles)"
check "… and gets an explanation" "do not grant" "$(curl -s -b "$WORK/vic" $O/roles)"
check "menu hides pages without rights" "0" "$(curl -s -b "$WORK/vic" $O/account | grep -c 'href="/roles"' || true)"
check "role rights change at once" "200" \
  "$(post "$WORK/cookies" /roles/ops -d 'label=Operators&rights=status.read&rights=users.read&rights=roles.read')"
check "… vic now sees roles" "200" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/vic" $O/roles)"

echo "Sites, files, monitoring"
check "/ shows the default site without sign-in" "This is the default site" "$(curl -s $O/)"
check "create site 'shop' (host shop.test, de + en)" "200" \
  "$(post "$WORK/cookies" /sites --data-urlencode 'key=shop' --data-urlencode 'name=Shop' \
    --data-urlencode 'hosts=shop.test' --data-urlencode 'defaultLanguage=de' --data-urlencode 'languages=en')"
check "German content" "200" "$(post "$WORK/cookies" /sites/shop/content --data-urlencode 'language=de' \
  --data-urlencode 'title=Willkommen' --data-urlencode 'body=Hallo')"
check "English content" "200" "$(post "$WORK/cookies" /sites/shop/content -d 'language=en&title=Welcome')"
check "host name selects the site, Accept-Language the language" "Welcome" \
  "$(curl -s -H 'Host: shop.test' -H 'Accept-Language: en-GB,en;q=0.9' $O/)"
check "?lang= overrides" "Willkommen" "$(curl -s -H 'Host: shop.test' -H 'Accept-Language: en' "$O/?lang=de")"
check "Content-Language header" "de" \
  "$(curl -s -o /dev/null -D - -H 'Host: shop.test' $O/ | tr -d '\r' | sed -n 's/^Content-Language: //p')"
check "unknown hosts get the default site" "This is the default site" "$(curl -s -H 'Host: other.test' $O/)"
printf 'GIF89a' > "$WORK/logo.gif"; printf '<script>alert(1)</script>' > "$WORK/page.html"
check "upload two files (multipart)" "200" "$(post "$WORK/cookies" /files/upload -F site=shop -F isPublic=on \
  -F "files=@$WORK/logo.gif" -F "files=@$WORK/page.html")"
check "files are stored on disk per site" "2" "$(ls "$WORK/data/open/files/shop" | wc -l | tr -d ' ')"
media=$(curl -s -H 'Host: shop.test' $O/ | grep -o '/media/shop/[^"]*page.html' | head -1)
check "public HTML is only offered as a download" "attachment; filename=\"page.html\"" \
  "$(curl -s -o /dev/null -D - "$O$media" | tr -d '\r' | sed -n 's/^Content-Disposition: //p')"
check "… as application/octet-stream" "application/octet-stream" "$(curl -s -o /dev/null -w '%{content_type}' "$O$media")"
check "create editor 'eve' limited to shop" "200" "$(post "$WORK/cookies" /users \
  -d 'userName=eve&roles=editor&scope=some&sites=shop&active=on&password=eve-password-1&confirm=eve-password-1')"
curl -s -o /dev/null -c "$WORK/eve" -d 'user=eve&password=eve-password-1' $O/login
check "eve only sees her site" "1" "$(curl -s -b "$WORK/eve" $O/sites | grep -c 'fw-normal">' || true)"
check "eve cannot open the default site's settings (error toast)" '"error":true' \
  "$(curl -s -o /dev/null -D - -b "$WORK/eve" -H 'HX-Request: true' $O/sites/main/edit | grep -i '^HX-Trigger')"
post "$WORK/cookies" /files/upload -F site=main -F "files=@$WORK/logo.gif" >/dev/null
mainfile=$(curl -s -b "$WORK/cookies" "$O/files?site=main" | grep -o '/files/[^/]*/download' | head -1)
check "… nor download its files" "404" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/eve" "$O$mainfile")"
check "… which the administrator can" "200" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/cookies" "$O$mainfile")"
check "eve has no monitoring" "403" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/eve" $O/monitoring)"
check "monitoring page" "Requests per minute" "$(curl -s -b "$WORK/cookies" $O/monitoring)"
check "metrics (Prometheus, local scraper)" "neko_http_requests_total" "$(curl -s $O/metrics)"
check "… with the files per site" 'neko_site_files{domain="open",site="shop"} 2' "$(curl -s $O/metrics)"
check "CLI lists the sites" "shop.test" "$("$BIN/platform-open" sites list)"
check "a site with files cannot be removed" "still has 2 files" \
  "$("$BIN/platform-open" sites remove shop 2>&1 || true)"

echo "Firewall, IP lists, traffic"
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
check "SQL injection refused" "403" "$(code -H 'X-Forwarded-For: 198.51.100.1' "$O/?q=1%27%20OR%20%271%27=%271")"
check "XSS in a form refused" "403" \
  "$(code -H 'X-Forwarded-For: 198.51.100.1' -H "Origin: $O" -d 'user=%3Cscript%3Ex%3C/script%3E&password=x' $O/login)"
check "scanner probe refused" "403" "$(code -H 'X-Forwarded-For: 198.51.100.1' $O/wp-login.php)"
check "API callers get JSON" '"code":"Forbidden"' \
  "$(curl -s -H 'X-Forwarded-For: 198.51.100.1' "$O/rest/v1/services?f=../../etc/passwd")"
check "passwords are not inspected" "401" \
  "$(code -H 'X-Forwarded-For: 198.51.100.2' -H "Origin: $O" --data-urlencode 'user=admin' --data-urlencode "password=' or 1=1 --" $O/login)"
check "security page" "Firewall events" "$(curl -s -b "$WORK/cookies" $O/security)"
check "… lists the attacker" "198.51.100.1" "$(curl -s -b "$WORK/cookies" $O/security/live)"
check "eve has no security page" "403" "$(code -b "$WORK/eve" $O/security)"
check "allow list refuses to lock out the caller" "lock you out" \
  "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" -H "X-CSRF-Token: $csrf" \
    -d 'network=10.0.0.0/8&action=allow&scope=admin' $O/security/rules)"
"$BIN/platform-open" firewall allow 127.0.0.1 --scope=admin --note=local >/dev/null
"$BIN/platform-open" firewall deny 203.0.113.0/24 --scope=all >/dev/null
sleep 6 # the server re-reads the rules within 5 seconds
check "CLI deny rule blocks everything" "403" "$(code -H 'X-Forwarded-For: 203.0.113.9' $O/)"
check "allow list closes the management pages to others" "403" "$(code -H 'X-Forwarded-For: 192.0.2.1' $O/login)"
check "… but not the public site" "200" "$(code -H 'X-Forwarded-For: 192.0.2.1' $O/)"
check "… while listed addresses get in" "200" "$(code -b "$WORK/cookies" $O/security)"
check "firewall check (CLI)" "blocked" "$("$BIN/platform-open" firewall check 192.0.2.1)"
check "traffic metrics" "neko_network_bytes_total" "$(curl -s $O/metrics)"
check "firewall metrics" 'neko_firewall_events_total{domain="open",rule="sqli"}' "$(curl -s $O/metrics)"

echo "Landscape and billing"
check "landscape page" "Hierarchy" "$(curl -s -b "$WORK/cookies" $O/landscape)"
check "default subaccount hosts the default site" "platform-open" "$("$BIN/platform-open" landscape)"
check "create directory 'retail' with its own budget" "200" "$(post "$WORK/cookies" /landscape/directories \
  -d 'key=retail&name=Retail&manageEntitlements=on&costCenter=CC-7&owner=jane')"
check "entitle the directory" "200" "$(post "$WORK/cookies" /landscape/entitlement -d 'node=directory:retail&plan=sites.site&quota=2')"
check "over-assignment refused" "assigned below, but only" "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" \
  -H "X-CSRF-Token: $csrf" -d 'node=directory:retail&plan=sites.site&quota=99' $O/landscape/entitlement)"
check "create subaccount with scheme subdomain" "200" "$(post "$WORK/cookies" /landscape/subaccounts \
  -d 'key=retail-prod&name=Retail&directory=retail&region=eu11&purpose=shop&stage=prod&sites=shop')"
check "… subdomain from the scheme" "shop-prod" "$("$BIN/platform-open" landscape show subaccount:retail-prod)"
check "… draws from the directory" "directory:retail" "$("$BIN/platform-open" landscape show subaccount:retail-prod)"
check "a site belongs to one subaccount" "also assigned" "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" \
  -H "X-CSRF-Token: $csrf" -d 'key=retail-dev&name=x&directory=retail&region=eu10&stage=dev&sites=shop' $O/landscape/subaccounts)"
check "region cannot change" "cannot change" "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" \
  -H "X-CSRF-Token: $csrf" -d 'name=Retail&directory=retail&region=us10&stage=prod&sites=shop' $O/landscape/subaccounts/retail-prod)"
check "eve has no landscape" "403" "$(code -b "$WORK/eve" $O/landscape)"
check "billing page" "Costs by hierarchy" "$(curl -s -b "$WORK/cookies" $O/landscape/billing)"
check "billing CSV" "month;subaccount;cost_center" "$(curl -s -b "$WORK/cookies" $O/landscape/billing.csv)"
check "landscape check (CLI)" "0" "$("$BIN/platform-open" landscape check >/dev/null; echo $?)"

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed. Logs: open.log / secret.log in $WORK"
  trap - EXIT
  exit 1
fi
echo "All checks passed."
