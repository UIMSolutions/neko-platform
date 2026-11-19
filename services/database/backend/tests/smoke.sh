#!/usr/bin/env bash
# End-to-end check against a running server: REST, cloud REST, cloud OData v4, assistant.
# Usage: HDB_URL=http://localhost:8080 ADMIN_PASSWORD=... SYSTEM_ADMIN_PASSWORD=... tests/smoke.sh
# Creates the instance "smoke" and the data product tables of bdc.hr.workforce, and removes both again.
set -euo pipefail
B=${HDB_URL:-http://localhost:8080}
H='Content-Type: application/json'
fail() { echo "FAIL: $*" >&2; exit 1; }
login() {
  curl -fsS -X POST "$B/api/v1/auth/login" -H "$H" -d "{\"tenant\":\"$1\",\"user\":\"$2\",\"password\":\"$3\"}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])'
}
call() { local t=$1; shift; curl -fsS -H "Authorization: Bearer $t" "$@"; }

curl -fsS "$B/health" | grep -q UP || fail "health"
SYS=$(login system "${SYSTEM_ADMIN_USER:-sysadmin}" "${SYSTEM_ADMIN_PASSWORD:?}")
ADM=$(login default "${ADMIN_USER:-admin}" "${ADMIN_PASSWORD:?}")

call "$SYS" -X POST "$B/api/v1/cloud/instances" -H "$H" \
  -d '{"name":"smoke","memoryGb":32,"adminName":"boss","adminPassword":"correct-horse-smoke1"}' | grep -q '"status":"running"' || fail "create instance"
call "$SYS" "$B/odata/v4/cloud/Instances" | grep -q '"name":"smoke"' || fail "OData Instances"
call "$SYS" -X POST "$B/api/v1/cloud/instances/smoke/stop" | grep -q stopped || fail "stop instance"
call "$SYS" -X DELETE "$B/api/v1/cloud/instances/smoke" || fail "delete instance"

call "$ADM" -X POST "$B/api/v1/dataproducts/bdc.hr.workforce/install" | grep -q bdc_hr_workforce__headcount || fail "install product"
call "$ADM" -X PUT "$B/api/v1/views/SMOKE_HEADCOUNT" -H "$H" -d '{"baseTable":"bdc_hr_workforce__headcount",
  "attributes":[{"column":"country","label":"COUNTRY"}],"measures":[{"column":"employees","aggregation":"sum","label":"EMPLOYEES"}]}' >/dev/null || fail "save view"
call "$ADM" "$B/odata/v4/cloud/CV_SMOKE_HEADCOUNT?\$count=true" | grep -q '"@odata.count":4' || fail "OData calculation view"
call "$ADM" "$B/odata/v4/cloud/\$metadata" | grep -q 'EntitySet Name="Recommendations"' || fail "cloud metadata"
call "$ADM" -X POST "$B/api/v1/assistant" -H "$H" -d '{"message":"status; how do I restore a backup?"}' | grep -q safety || fail "assistant"
call "$ADM" "$B/api/v1/monitoring/issues" | grep -q '"text"' || fail "issue summary"
call "$ADM" -X POST "$B/api/v1/advisors/run" -H "$H" -d '{}' >/dev/null || fail "advisors"
call "$ADM" -X DELETE "$B/api/v1/views/SMOKE_HEADCOUNT" || fail "delete view"
call "$ADM" -X DELETE "$B/api/v1/dataproducts/bdc.hr.workforce/install" || fail "uninstall product"
echo "smoke test passed"
