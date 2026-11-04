#!/bin/bash
# Regression check on dev for mid-session Galaxy key recovery (commit 9503abf5e).
#
# Reproduces the real failure: log in as the E2E fixture (key valid), then soft-delete that
# account's newest active Galaxy API key in dev's Galaxy DB — what the pre-2edb4d4a5 boot seed
# did on every Galaxy restart — and send a chat workflow request on the SAME session (no
# re-login). Pre-fix: workflow_failed / 401 "Provided API key is not valid." Post-fix: the
# proxy re-provisions once, retries, and the request returns workflow_ready.
#
# Safety: touches only the fixture's own key row (Galaxy user looked up by email), never a row
# whose value equals the container's GALAXY_API_KEY (the bootstrap/admin key); key values are
# compared inside the container and never printed. Requires E2E_FIXTURE_PASSWORD.
set -euo pipefail
: "${E2E_FIXTURE_PASSWORD:?E2E_FIXTURE_PASSWORD is not set}"
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

echo "2) revoke the fixture's newest active Galaxy key (simulates the restart bug)"
dev "sudo docker exec -i biomate-galaxy-dev python3 -" <<PY
import os, sqlite3
env = os.environ.get("GALAXY_API_KEY", "").strip()
c = sqlite3.connect("/app/database/universe.sqlite")
uid = c.execute("select id from galaxy_user where lower(email)=lower(?)", ("$EMAIL",)).fetchone()
assert uid, "fixture not found in Galaxy"
row = c.execute("select id, key from api_keys where user_id=? and deleted=0 and key != ? order by id desc limit 1", (uid[0], env)).fetchone()
assert row, "fixture has no active personal key"
c.execute("update api_keys set deleted=1 where id=?", (row[0],)); c.commit()
print(f"   revoked key row {row[0]} of Galaxy user {uid[0]}")
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
