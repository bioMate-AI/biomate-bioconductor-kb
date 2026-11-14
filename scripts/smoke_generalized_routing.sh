#!/usr/bin/env bash
# Smoke harness for the 2026-11-04 generalizations (model-training + multi-omics).
# Readiness-style: safe to run with the flags OFF (reports "flag off, expected"),
# and PASSES once ML_TRAINING_ROUTING=1 + MULTIOMICS_ROUTING=1 are set on dev.
#
# Follows scripts/e2e_use_cases.sh conventions: single canonical fixture, live
# dev stack (NO mocks), login once, 90s LLM budget for workflow cards.
#   BIOMATE_URL        override target (default dev)
#   E2E_FIXTURE_PASSWORD   fixture password (required)
#   EXPECT_FLAGS_ON=1  turn flag-off into a hard FAIL (use after flipping flags)
set -uo pipefail

BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"
FIXTURE_EMAIL="${FIXTURE_EMAIL:-lifeifei163361@163.com}"
FIXTURE_PASSWORD="${E2E_FIXTURE_PASSWORD:-${FIXTURE_PASSWORD:-}}"
EXPECT_FLAGS_ON="${EXPECT_FLAGS_ON:-0}"
LOG_DIR="${LOG_DIR:-/tmp/smoke_generalized}"; mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
PASS=0; FAIL=0; FLAGOFF=0

note()  { printf '%s\n' "$*"; }
POST() { # POST <path> <jwt> <json>  — TIMEOUT env for LLM paths
  curl -sS --max-time "${TIMEOUT:-45}" -X POST "$BIOMATE_URL$1" \
    -H "Content-Type: application/json" \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    ${2:+-H "Authorization: Bearer $2"} \
    -d "$3"
}
pass() { PASS=$((PASS+1)); note "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); note "  ✗ $1"; }
flagoff() { FLAGOFF=$((FLAGOFF+1)); note "  ⊘ $1 — routing fell through (flag off?)"; }
routed_name() { grep -oE '"name":"[^"]{0,48}' "$1" | head -1 | sed -E 's/.*"name":"//'; }

note "target:  $BIOMATE_URL"
note "fixture: $FIXTURE_EMAIL"
[ -n "$FIXTURE_PASSWORD" ] || { note "ERROR: set E2E_FIXTURE_PASSWORD"; exit 2; }

# ── login once ──────────────────────────────────────────────────────
LOGIN="$(POST /api/auth/login "" "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\"}")"
JWT="$(printf '%s' "$LOGIN" | python3 -c "import sys,json;print(json.load(sys.stdin).get('token',''))" 2>/dev/null)"
[ "${#JWT}" -ge 20 ] && pass "fixture login" || { fail "fixture login (resp: ${LOGIN:0:120})"; exit 1; }

chat() { # chat <sessionTag> <message> -> writes stream to a log, echoes path
  local tag="$1" msg="$2"
  local f="$LOG_DIR/${TS}_${tag}"
  TIMEOUT=90 POST /api/chat/stream "$JWT" \
    "{\"message\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$msg"),\"stream\":true,\"context\":{\"sessionId\":\"smoke-${tag}-$(date +%s)\",\"previousMessages\":[]}}" \
    > "$f" 2>&1
  printf '%s' "$f"
}

# ── 1. model-training: expression matrix → subtype, 5-fold CV ────────
note ""; note "1. model-training routing (expression matrix → subtype, 5-fold CV)"
F1="$(chat mltrain "Train a subtype prediction model on this gene expression matrix with 5-fold cross-validation.")"
# DEFINITIVE signal only (loose words like "cross-validation" also match the LLM's
# reasoning and the unrelated DaMiRseq workflow — verified false positives).
if grep -qE 'sklearn_tabular|"source": *"ml_training"' "$F1"; then
  pass "routed to generic tabular training (sklearn_tabular)"
else
  flagoff "model-training NOT routed to sklearn_tabular"
  RN="$(routed_name "$F1")"; note "      instead routed to: ${RN:-?}"
fi

# ── 2. multi-omics: zh spatial+proteomics+metabolomics → 分型 ────────
note ""; note "2. multi-omics routing (zh 整合空间转录组+蛋白质组+代谢组 → 患者分型)"
F2="$(chat multiomics "整合空间转录组、蛋白质组和代谢组数据做患者分型")"
# DEFINITIVE signal only ("整合"/"multi-omics" also match the reasoning text).
if grep -qE '"source": *"multiomics"|"method": *"SNF"|Similarity Network Fusion' "$F2"; then
  pass "routed to multi-omics integration (SNF plan)"
else
  flagoff "multi-omics NOT routed to the integration engine"
  RN="$(routed_name "$F2")"; note "      instead routed to: ${RN:-?}"
fi

# ── summary ─────────────────────────────────────────────────────────
note ""; note "── summary: $PASS pass / $FAIL fail / $FLAGOFF flag-off ──"
note "logs: $LOG_DIR/${TS}_*"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
if [ "$FLAGOFF" -gt 0 ]; then
  if [ "$EXPECT_FLAGS_ON" = "1" ]; then note "FAIL: flags expected ON but routing fell through"; exit 1; fi
  note "READY: harness works; flip ML_TRAINING_ROUTING=1 + MULTIOMICS_ROUTING=1 on dev, then rerun with EXPECT_FLAGS_ON=1."
fi
exit 0
