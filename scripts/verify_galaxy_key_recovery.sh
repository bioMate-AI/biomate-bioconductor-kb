#!/bin/bash
# Regression check on dev for mid-session Galaxy key recovery (commit 9503abf5e).
#
# Reproduces the real failure: log in as the E2E fixture (key valid), then delete that
# account's current Galaxy API key through Galaxy's admin API — what the pre-2edb4d4a5 boot seed
# did on every Galaxy restart — and send a chat workflow request on the SAME session (no
# re-login). Pre-fix: workflow_failed / 401 "Provided API key is not valid." Post-fix: the
# proxy re-provisions once, retries, and the request returns workflow_ready.
#
# Safety: touches only the fixture's own key row (Galaxy user looked up by email), never a row
# whose value equals the container's GALAXY_API_KEY (the bootstrap/admin key); key values are
# compared inside the container and never printed. Password: E2E_FIXTURE_PASSWORD, else ~/.config/biomate/e2e_fixture_password.
set -euo pipefail
PW_FILE="$HOME/.config/biomate/e2e_fixture_password"  # local, chmod 600, never committed
[[ -z "${E2E_FIXTURE_PASSWORD:-}" && -r "$PW_FILE" ]] && E2E_FIXTURE_PASSWORD=$(cat "$PW_FILE")
: "${E2E_FIXTURE_PASSWORD:?set E2E_FIXTURE_PASSWORD or create $PW_FILE}"
export E2E_FIXTURE_PASSWORD
BASE="${BIOMATE_URL:-https://dev-public.biomate.ai}"
EMAIL="lifeifei163361@163.com"
export PATH="$HOME/bin:$PATH"
INSTANCE_ID="i-06696b0d91f4346e0"; KEY_FILE="/tmp/biomate_ec2_key_sync"
PROXY="aws ssm start-session --target ${INSTANCE_ID} --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2"
[[ -f "$KEY_FILE" ]] || ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" -q
dev() {
  aws ec2-instance-connect send-ssh-public-key --instance-id "$INSTANCE_ID" --availability-zone us-west-2a \
    --instance-os-user ubuntu --ssh-public-key "file://${KEY_FILE}.pub" --region us-west-2 --output text --query Success </dev/null >/dev/null
  ssh -i "$KEY_FILE" -o ProxyCommand="$PROXY" -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o IdentitiesOnly=yes \
    -o LogLevel=ERROR "ubuntu@${INSTANCE_ID}" "$@"
}

echo "1) login (session kept for the rest of the check)"
TOKEN=$(curl -s -m 60 -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d "$(python3 -c "import json,os;print(json.dumps({'email':'$EMAIL','password':os.environ['E2E_FIXTURE_PASSWORD']}))")" \
  | python3 -c "import sys,json;print(json.load(sys.stdin).get('token',''))")
[[ ${#TOKEN} -gt 50 ]] || { echo "FAIL: login"; exit 1; }

echo "2) revoke the fixture's current Galaxy key via Galaxy's own API (simulates the restart bug)"
# DELETE /api/users/{id}/api_key marks the user's current key deleted (Galaxy UserManager path,
# admin-authorised with the container's bootstrap key) — same effect as the old boot seed, no SQL.
dev "sudo docker exec -i biomate-galaxy-dev python3 -" <<PY
import json, os, urllib.request
k = os.environ["GALAXY_API_KEY"].strip()
def call(method, path):
    r = urllib.request.Request("http://localhost:8080" + path, method=method, headers={"x-api-key": k})
    with urllib.request.urlopen(r, timeout=30) as resp:
        return resp.status, resp.read().decode()
st, body = call("GET", "/api/users?f_email=$EMAIL")
users = [u for u in json.loads(body) if u.get("email", "").lower() == "$EMAIL".lower()]
assert users, "fixture not found in Galaxy"
st, _ = call("DELETE", f"/api/users/{users[0]['id']}/api_key")
print(f"   DELETE api_key for Galaxy user {users[0]['id']} -> HTTP {st}")
PY

echo "3) workflow request on the SAME session (no re-login)"
SINCE=$(date -u +%Y-%m-%dT%H:%M:%S)
OUT=$(curl -s -N -m 240 -X POST "$BASE/api/chat/stream" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"message":"Run perform_chipseq_peak_calling_with_macs2 using its built-in MACS3 CTCF_SE ChIP and control chr22 50k-read BED demo files. Use the real public demo defaults.","stream":true,"context":{"sessionId":"key-recovery-check","previousMessages":[]}}' \
  | sed -n '/^event: final/{n;p;q}')
STATE=$(printf '%s' "$OUT" | python3 -c "import sys,json;
d=sys.stdin.read().strip()
print(json.loads(d[d.index('{'):]).get('state') if '{' in d else 'none')")
echo "   final state: $STATE"

echo "4) evidence in the dev frontend log"
dev "sudo docker logs biomate-dev-frontend --since $SINCE 2>&1 | grep -E 'rejected .*mid-session|Provided API key is not valid' | cut -c1-160 | head -5"

if [[ "$STATE" == "workflow_ready" ]]; then echo "PASS: session recovered from a revoked Galaxy key"; else echo "FAIL: state=$STATE"; exit 1; fi
