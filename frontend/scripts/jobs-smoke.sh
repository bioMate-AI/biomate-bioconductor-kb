#!/usr/bin/env bash
# Phase 0 async-job-queue smoke test.
#
# Posts a stub job, polls until ready, downloads the artifact.
# Requires the Node API to be running locally on $BASE (default :5000)
# and a JWT cookie/header for an authenticated user passed as $AUTH_HEADER
# (e.g. "Authorization: Bearer …" or "Cookie: token=…").
#
# Usage:
#   AUTH_HEADER="Cookie: token=..." ./scripts/jobs-smoke.sh

set -euo pipefail
BASE="${BASE:-http://localhost:5000}"
AUTH_HEADER="${AUTH_HEADER:-}"

if [ -z "$AUTH_HEADER" ]; then
  echo "AUTH_HEADER required (e.g. 'Cookie: token=...')" >&2
  exit 1
fi

echo "POST /api/jobs (stub kind)…"
RESP=$(curl -fsS -X POST "$BASE/api/jobs" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"kind":"download_all_zip_v0_stub","payload":{"invocationId":"smoke-1"}}')
echo "$RESP"
JOB_ID=$(echo "$RESP" | python3 -c 'import sys,json; print(json.load(sys.stdin)["jobId"])')

for i in $(seq 1 30); do
  STATE=$(curl -fsS "$BASE/api/jobs/$JOB_ID" -H "$AUTH_HEADER" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["state"])')
  echo "tick $i: state=$STATE"
  if [ "$STATE" = "ready" ]; then break; fi
  if [ "$STATE" = "failed" ] || [ "$STATE" = "cancelled" ]; then
    echo "job terminated: $STATE" >&2
    exit 1
  fi
  sleep 1
done

echo "GET /api/jobs/$JOB_ID/artifact"
OUT=$(mktemp)
curl -fsS "$BASE/api/jobs/$JOB_ID/artifact" -H "$AUTH_HEADER" -o "$OUT"
SIZE=$(wc -c < "$OUT")
echo "artifact bytes: $SIZE (expected 100)"
test "$SIZE" -eq 100 || { echo "size mismatch"; exit 1; }
echo "OK"
