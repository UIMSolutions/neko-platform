#!/usr/bin/env bash
# End-to-end smoke test of two platform instances (open → secret).
#
#   dub build --config=open && dub build --config=secret
#   backend/tests/smoke.sh
#
# Uses throw-away ports and data directories; needs curl and python3.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$ROOT/backend/build"
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
NEKO_PORT=$OPEN_PORT NEKO_ADMIN_PASSWORD=smoke-admin-pw "$BIN/platform-open" >"$WORK/open.log" 2>&1 & PIDS+=($!)
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
check "embedded Beer CSS" "200" "$(curl -s -o /dev/null -w '%{http_code}' $O/ui/beer-5.0.3.min.css)"

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed. Logs: open.log / secret.log in $WORK"
  trap - EXIT
  exit 1
fi
echo "All checks passed."
