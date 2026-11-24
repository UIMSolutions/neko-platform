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

echo "Files, monitoring"
check "/ leads to the sign-in" "/login" "$(curl -s -o /dev/null -w '%{redirect_url}' $O/)"
check "… or, signed in, to the pages" "/start" "$(curl -s -o /dev/null -w '%{redirect_url}' -b "$WORK/cookies" $O/)"
check "create subaccount shop-dev" "200" "$(post "$WORK/cookies" /landscape/subaccounts \
  -d 'key=shop-dev&name=Shop&region=eu10&purpose=shop&stage=dev')"
printf 'GIF89a' > "$WORK/logo.gif"; printf '<script>alert(1)</script>' > "$WORK/page.html"
check "upload two files to shop-dev (multipart)" "200" "$(post "$WORK/cookies" /files/upload -F subaccount=shop-dev \
  -F isPublic=on -F "files=@$WORK/logo.gif" -F "files=@$WORK/page.html")"
check "files are stored on disk per subaccount" "2" "$(ls "$WORK/data/open/files/shop-dev" | wc -l | tr -d ' ')"
media=$(curl -s -b "$WORK/cookies" "$O/files?subaccount=shop-dev" | grep -o '/media/shop-dev/[^"]*page.html' | head -1)
check "public files need no sign-in" "200" "$(curl -s -o /dev/null -w '%{http_code}' "$O$media")"
check "public HTML is only offered as a download" "attachment; filename=\"page.html\"" \
  "$(curl -s -o /dev/null -D - "$O$media" | tr -d '\r' | sed -n 's/^Content-Disposition: //p')"
check "… as application/octet-stream" "application/octet-stream" "$(curl -s -o /dev/null -w '%{content_type}' "$O$media")"
check "create editor 'eve'" "200" "$(post "$WORK/cookies" /users \
  -d 'userName=eve&roles=editor&active=on&password=eve-password-1&confirm=eve-password-1')"
check "eve joins the user group of shop-dev" "user group: eve" \
  "$("$BIN/platform-open" landscape access shop-dev --members=eve)"
curl -s -o /dev/null -c "$WORK/eve" -d 'user=eve&password=eve-password-1' $O/login
check "eve only sees the library of shop-dev" "0" \
  "$(curl -s -b "$WORK/eve" $O/files | grep -c 'value="platform-open"' || true)"
check "… with its files" "page.html" "$(curl -s -b "$WORK/eve" "$O/files?subaccount=shop-dev")"
post "$WORK/cookies" /files/upload -F subaccount=platform-open -F "files=@$WORK/logo.gif" >/dev/null
mainfile=$(curl -s -b "$WORK/cookies" "$O/files?subaccount=platform-open" | grep -o '/files/[^/]*/download' | head -1)
check "eve cannot download files of other subaccounts" "404" \
  "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/eve" "$O$mainfile")"
check "… which the administrator can" "200" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/cookies" "$O$mainfile")"
check "eve has no monitoring" "403" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/eve" $O/monitoring)"
check "monitoring page" "Requests per minute" "$(curl -s -b "$WORK/cookies" $O/monitoring)"
check "metrics (Prometheus, local scraper)" "neko_http_requests_total" "$(curl -s $O/metrics)"
check "… with the files per subaccount" 'neko_subaccount_files{domain="open",subaccount="shop-dev"} 2' \
  "$(curl -s $O/metrics)"
check "CLI lists the files per subaccount" "shop-dev" "$("$BIN/platform-open" files usage)"
check "a subaccount with files cannot be removed" "still has 2 files" "$(curl -s -D - -o /dev/null -b "$WORK/cookies" \
  -H "Origin: $O" -H "HX-Request: true" -H "X-CSRF-Token: $csrf" -X POST $O/landscape/subaccounts/shop-dev/delete)"
check "sites are gone" "404" "$(curl -s -o /dev/null -w '%{http_code}' -b "$WORK/cookies" $O/sites)"

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
check "… but not the public files" "200" "$(code -H 'X-Forwarded-For: 192.0.2.1' "$O$media")"
check "… while listed addresses get in" "200" "$(code -b "$WORK/cookies" $O/security)"
check "firewall check (CLI)" "blocked" "$("$BIN/platform-open" firewall check 192.0.2.1)"
check "traffic metrics" "neko_network_bytes_total" "$(curl -s $O/metrics)"
check "firewall metrics" 'neko_firewall_events_total{domain="open",rule="sqli"}' "$(curl -s $O/metrics)"

echo "Landscape and billing"
check "landscape page" "Hierarchy" "$(curl -s -b "$WORK/cookies" $O/landscape)"
check "the first subaccount runs this instance" "platform-open" "$("$BIN/platform-open" landscape)"
check "create directory 'retail' with its own budget" "200" "$(post "$WORK/cookies" /landscape/directories \
  -d 'key=retail&name=Retail&manageEntitlements=on&costCenter=CC-7&owner=jane')"
check "entitle the directory" "200" "$(post "$WORK/cookies" /landscape/entitlement -d 'node=directory:retail&plan=files.storage&quota=20')"
check "over-assignment refused" "assigned below, but only" "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" \
  -H "X-CSRF-Token: $csrf" -d 'node=directory:retail&plan=files.storage&quota=99' $O/landscape/entitlement)"
check "create subaccount with scheme subdomain" "200" "$(post "$WORK/cookies" /landscape/subaccounts \
  -d 'key=retail-prod&name=Retail&directory=retail&region=eu11&purpose=shop&stage=prod')"
check "… subdomain from the scheme" "shop-prod" "$("$BIN/platform-open" landscape show subaccount:retail-prod)"
check "… draws from the directory" "directory:retail" "$("$BIN/platform-open" landscape show subaccount:retail-prod)"
check "region cannot change" "cannot change" "$(curl -s -b "$WORK/cookies" -H "Origin: $O" -H "HX-Request: true" \
  -H "X-CSRF-Token: $csrf" -d 'name=Retail&directory=retail&region=us10&stage=prod' $O/landscape/subaccounts/retail-prod)"
check "create tenant eu" "200" "$(post "$WORK/cookies" /landscape/subaccounts/retail-prod/tenants -d 'key=eu&name=Europe')"
check "… with a space qa" "200" "$(post "$WORK/cookies" /landscape/subaccounts/retail-prod/tenants/eu/spaces -d 'key=qa')"
check "the default space cannot be removed" "cannot be removed" "$(curl -s -D - -b "$WORK/cookies" -H "Origin: $O" \
  -H "HX-Request: true" -H "X-CSRF-Token: $csrf" -X POST $O/landscape/subaccounts/retail-prod/tenants/eu/spaces/default/delete)"
check "subaccount access (CLI)" "services: files, landscape" "$("$BIN/platform-open" landscape access retail-prod \
  --admins=admin --members=bob --services=landscape,files)"

echo "Service assignments"
check "assignment matrix" "Services × subaccounts" "$(curl -s -b "$WORK/cookies" $O/landscape/assignments)"
check "unassign files from shop-dev (web)" "200" \
  "$(post "$WORK/cookies" /landscape/assignments -d 'service=files&subaccount=shop-dev&assign=0')"
check "… uploads to shop-dev are refused" "not assigned" "$(curl -s -D - -o /dev/null -b "$WORK/cookies" -H "Origin: $O" \
  -H "HX-Request: true" -H "X-CSRF-Token: $csrf" -F subaccount=shop-dev -F "files=@$WORK/logo.gif" $O/files/upload)"
check "… its files stay reachable" "page.html" "$(curl -s -b "$WORK/cookies" "$O/files?subaccount=shop-dev")"
check "assign files to every subaccount (CLI)" "Assigned files" "$("$BIN/platform-open" landscape assign files all)"
check "… shop-dev has every service again" "[]" \
  "$("$BIN/platform-open" landscape show subaccount:shop-dev --json | json "['services']")"
check "matrix (CLI)" "SERVICE" "$("$BIN/platform-open" landscape assignments)"

echo "Disaster recovery"
check "recovery page" "unprotected" "$(curl -s -b "$WORK/cookies" $O/landscape/recovery)"
check "production without a plan is advised" "Set up disaster recovery" "$("$BIN/platform-open" landscape check)"
check "plan for retail-prod (CLI)" "protected" "$("$BIN/platform-open" landscape recovery plan retail-prod \
  --secondary=eu20 --strategy=pilot-light --rpo=10 --rto=45)"
check "the secondary region must differ (web)" "must differ" "$(curl -s -b "$WORK/cookies" -H "Origin: $O" \
  -H "HX-Request: true" -H "X-CSRF-Token: $csrf" -d 'enabled=on&secondaryRegion=eu10&strategy=warm-standby&rpoMinutes=15&rtoMinutes=60' \
  $O/landscape/recovery/shop-dev/plan)"
check "drill within the RTO (web)" "passed" "$(curl -s -D - -o /dev/null -b "$WORK/cookies" -H "Origin: $O" \
  -H "HX-Request: true" -H "X-CSRF-Token: $csrf" -d 'minutes=30&worked=on&reason=smoke' \
  $O/landscape/recovery/retail-prod/drill)"
check "drill over the RTO fails (CLI, exit 1)" "1" \
  "$("$BIN/platform-open" landscape recovery drill retail-prod --minutes=90 >/dev/null 2>&1; echo $?)"
check "failover (web)" "200" "$(post "$WORK/cookies" /landscape/recovery/retail-prod/failover -d 'reason=smoke+test&minutes=12')"
check "… calls run in the secondary region" "X-Neko-Region: eu20" "$(curl -s -D - -o /dev/null \
  -H 'X-Neko-Subaccount: retail-prod' $O/rest/v1/context | tr -d '\r')"
check "… a failed-over subaccount cannot change its region" "fail back first" \
  "$("$BIN/platform-open" landscape recovery plan retail-prod --secondary=eu30 2>&1 || true)"
check "failback (CLI)" "runs in eu11" "$("$BIN/platform-open" landscape recovery failback retail-prod --reason=healthy)"
check "history of the plan" "failback eu20 → eu11" "$("$BIN/platform-open" landscape recovery show retail-prod)"
check "recovery list (CLI)" "1 protected" "$("$BIN/platform-open" landscape recovery)"

echo "Account model: call context, global accounts"
check "default call context" '"subaccount":"platform-open"' "$(curl -s $O/rest/v1/context)"
check "tenant and space by header" '"space":"qa"' "$(curl -s -H 'X-Neko-Subaccount: retail-prod' \
  -H 'X-Neko-Tenant: eu' -H 'X-Neko-Space: qa' $O/rest/v1/context)"
check "tenant by subdomain" "X-Neko-Tenant: eu" "$(curl -s -D - -o /dev/null \
  -H "Host: eu.$("$BIN/platform-open" landscape show subaccount:retail-prod --json | json "['subdomain']").example" \
  $O/rest/v1/overview | tr -d '\r')"
check "unknown tenant refused" "404" "$(code -H 'X-Neko-Tenant: nope' $O/rest/v1/overview)"
check "create global account acme (CLI)" "global-accounts/acme" "$("$BIN/platform-open" globals add --key=acme \
  --name=ACME --hosts=acme.localhost)"
check "acme is physically separate" "acme" "$(ls "$WORK/data/open/global-accounts")"
check "acme has its own users" "0" "$("$BIN/platform-open" --global=acme users --json | json "[0]['userName']" \
  | grep -c eve || true)"
check "requests naming acme go to acme" "X-Neko-Global-Account: acme" "$(curl -s -D - -o /dev/null \
  -H 'X-Neko-Global-Account: acme' $O/rest/v1/overview | tr -d '\r')"
check "… and so do those for acme.localhost" '"globalAccount":"acme"' "$(curl -s -H 'Host: acme.localhost' \
  $O/rest/v1/context)"
check "unknown global account refused" "404" "$(code -H 'X-Neko-Global-Account: nope' $O/rest/v1/overview)"
check "global accounts page (operator)" "global-accounts/acme" "$(curl -s -b "$WORK/cookies" $O/accounts)"
check "eve sees the landscape as a member of shop-dev" "200" "$(code -b "$WORK/eve" $O/landscape)"
check "… but cannot change the recovery of retail-prod" "403" "$(code -b "$WORK/eve" $O/landscape/recovery/retail-prod/plan)"
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
