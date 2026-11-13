#!/usr/bin/env bash
# test_llm_provider.sh — LLM provider compatibility smoke test
#
# Verifies that the configured LLM backend (Claude, Qwen, DeepSeek, etc.)
# correctly handles the 5 key response patterns BioMate depends on:
#
#   T1  SSE streaming:   ready + final events emitted within timeout
#   T2  Knowledge Q:     pure-text question → NOT workflow_ready
#   T3  Workflow intent: clear request → workflow_ready + valid name
#   T4  Clarification:   vague request → needs_input (NOT workflow_ready)
#   T5  Workflow struct: returned workflow has name / domain / non-empty
#   T6  Domain routing:  ADMET request → drug_discovery domain
#
# DEFAULT target: TEST (Qwen/on-prem simulation)
# Override:       BIOMATE_URL=https://dev-public.biomate.ai ./test_llm_provider.sh
#
# Per CLAUDE.md: single canonical fixture, NEVER call /api/auth/register.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO/docs/e2e_runs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="$LOG_DIR/${TS}_provider.log"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Precedence: BASE_URL > BIOMATE_URL > default (matches e2e/_e2e-base-url.ts)

export BIOMATE_URL="${BASE_URL:-${BIOMATE_URL:-https://test.stage-public.biomate.ai}}"

export BASE_URL="$BIOMATE_URL"
E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-test-e2e-token-12345}"
FIXTURE_EMAIL="${FIXTURE_EMAIL:-lifeifei163361@163.com}"
FIXTURE_PASSWORD="${FIXTURE_PASSWORD:-WpmFixture!2026}"

C_OK=$'\033[32m'   ; C_FAIL=$'\033[31m'
C_WARN=$'\033[33m' ; C_DIM=$'\033[2m'  ; C_RESET=$'\033[0m'

P0_FAILS=0 ; P1_FAILS=0 ; PASS_COUNT=0

heading() { printf "\n${C_WARN}── %s ──${C_RESET}\n" "$*" | tee -a "$RUN_LOG"; }
note()    { printf "%s\n" "$*" | tee -a "$RUN_LOG"; }
pass()    { printf "  ${C_OK}✓${C_RESET} %s\n" "$*" | tee -a "$RUN_LOG"; PASS_COUNT=$((PASS_COUNT+1)); }
fail()    {
  local prio="${1:-P0}"; shift
  printf "  ${C_FAIL}✗${C_RESET} [%s] %s\n      %s\n" "$prio" "$1" "$2" | tee -a "$RUN_LOG"
  [ "$prio" = "P0" ] && P0_FAILS=$((P0_FAILS+1)) || P1_FAILS=$((P1_FAILS+1))
}

# expect DESC ACTUAL REGEX [PRIO]
expect() {
  local desc="$1" actual="$2" rx="$3" prio="${4:-P0}"
  if echo "$actual" | grep -qE -- "$rx"; then
    pass "$desc"
  else
    fail "$prio" "$desc" "expected /$rx/, got: $(echo "$actual" | head -c 200)"
  fi
}

POST() {
  curl -sSkL -X POST "$BIOMATE_URL$1" \
    ${2:+-H "Authorization: Bearer $2"} \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    -H "content-type: application/json" \
    --max-time "${TIMEOUT:-30}" -d "${3:-}" 2>&1
}
DEL() {
  curl -sSkL -X DELETE "$BIOMATE_URL$1" \
    ${2:+-H "Authorization: Bearer $2"} \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    --max-time 15 2>&1
}

# Extract field from final SSE event data
# Usage: sse_final_field STREAM_FILE FIELD
sse_final_field() {
  local f="$1" field="$2"
  # Find "event: final" block, grab next data: line, extract JSON field
  grep -A1 "^event: final" "$f" 2>/dev/null \
    | grep "^data:" \
    | sed 's/^data: //' \
    | python3 -c "
import sys, json
try:
  d = json.loads(sys.stdin.read())
  keys = '$field'.split('.')
  v = d
  for k in keys:
    if isinstance(v, dict): v = v.get(k)
    else: v = None
  print('' if v is None else str(v))
except Exception as e:
  print('')
" 2>/dev/null || true
}

# ── Banner ───────────────────────────────────────────────────────────
note ""
note "${C_WARN}BioMate LLM Provider Compatibility Test${C_RESET}"
note "${C_DIM}target:  $BIOMATE_URL${C_RESET}"
note "${C_DIM}log:     $RUN_LOG${C_RESET}"
note "${C_DIM}fixture: $FIXTURE_EMAIL${C_RESET}"

# ── Login (once) ─────────────────────────────────────────────────────
heading "Setup: login + create project"

LOGIN_RESP="$(POST /api/auth/login "" \
  "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\"}")"
JWT="$(echo "$LOGIN_RESP" | python3 -c \
  "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('token',''))" 2>/dev/null || true)"

if [ -z "$JWT" ] || [ ${#JWT} -lt 20 ]; then
  fail "P0" "fixture login" "JWT empty — check credentials or server health"
  note "${C_FAIL}ABORT: cannot login, all downstream tests will fail.${C_RESET}"
  exit 1
fi
pass "fixture login (${#JWT} chars)"

P_CREATE="$(POST /api/projects "$JWT" \
  '{"name":"provider-test","primaryDomain":"transcriptomics"}')"
PID="$(echo "$P_CREATE" | python3 -c \
  "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('project',{}).get('id','') or d.get('id',''))" 2>/dev/null || true)"

cleanup() { [ -n "${PID:-}" ] && DEL "/api/projects/$PID" "$JWT" > /dev/null 2>&1 || true; }
trap 'rm -rf "$TMP_DIR"; cleanup' EXIT

if [ -z "$PID" ]; then
  fail "P0" "create project" "PID empty — response: $(echo "$P_CREATE" | head -c 200)"
  note "${C_FAIL}ABORT: cannot create project.${C_RESET}"
  exit 1
fi
pass "create project ($PID)"

# Helper: run one chat-stream test and save to a temp file
# Usage: chat_stream LABEL TIMEOUT_SECS MESSAGE [PREV_MSGS_JSON]
chat_stream() {
  local label="$1" tout="$2" msg="$3" prev="${4:-[]}"
  local out="$TMP_DIR/${label}.sse"
  local sess="provider-${label}-$$"
  TIMEOUT="$tout" POST /api/chat/stream "$JWT" \
    "{\"message\":\"$msg\",\"stream\":true,\"context\":{\"sessionId\":\"$sess\",\"projectId\":\"$PID\",\"previousMessages\":$prev}}" \
    > "$out" 2>&1
  echo "$out"
}

# ════════════════════════════════════════════════════════════════════
# T1 — SSE streaming: ready + final events within timeout
# ════════════════════════════════════════════════════════════════════
heading "T1 — SSE streaming (basic provider connectivity)"

F="$(chat_stream t1 45 "hello")"
EVENTS="$(grep -oE "^event: [a-z_]+" "$F" 2>/dev/null | sort -u | tr '\n' ' ')"
note "  events: $EVENTS"
expect "emits 'event: ready'"  "$EVENTS" "event: ready"
expect "emits 'event: final'"  "$EVENTS" "event: final"
expect "no HTTP error in stream" \
  "$(head -3 "$F")" "event:|data:" "P1"

# ════════════════════════════════════════════════════════════════════
# T2 — Knowledge question: must NOT return workflow_ready
# ════════════════════════════════════════════════════════════════════
heading "T2 — Knowledge routing (pure-text Q, no workflow needed)"

F="$(chat_stream t2 60 "What is Benjamini-Hochberg FDR correction and when should I use it in RNA-seq analysis?")"
STATE="$(sse_final_field "$F" "state")"
note "  state: $STATE"
expect "state is NOT workflow_ready (knowledge Q should not trigger workflow)" \
  "${STATE:-chat_only}" "^(chat_only|needs_input|workflow_failed)$"
# Also check there is substantive text (field is "response" not "text" in the SSE payload)
TEXT_LEN="$(sse_final_field "$F" "response" | wc -c | tr -d ' ')"
expect "response has text content (> 50 chars)" "${TEXT_LEN:-0}" "^([5-9][0-9]|[1-9][0-9]{2,})$" "P1"

# ════════════════════════════════════════════════════════════════════
# T3 — Workflow intent: clear request → workflow_ready + valid name
# ════════════════════════════════════════════════════════════════════
heading "T3 — Workflow generation (clear request with enough info)"

F="$(chat_stream t3 120 \
  "Run DESeq2 differential expression analysis on my RNA-seq data. I have a count matrix comparing tumor vs normal samples.")"
STATE="$(sse_final_field "$F" "state")"
WF_EVENT="$(grep -oE "workflow_(ready|failed)" "$F" 2>/dev/null | head -1)"
WF_NAME="$(sse_final_field "$F" "workflow.workflow_ga.name")"
note "  state: $STATE  |  event: $WF_EVENT  |  workflow.name: $WF_NAME"

expect "state is workflow_ready"   "${STATE:-}"    "^workflow_ready$"
expect "workflow_ready event emitted" "${WF_EVENT:-}" "^workflow_ready$"
expect "workflow.name is not empty or 'undefined'" \
  "${WF_NAME:-}" "^.{3,}$"
if echo "${WF_NAME:-}" | grep -qi "undefined"; then
  fail "P0" "workflow.name must not be literal 'undefined'" "got: $WF_NAME"
fi

# ════════════════════════════════════════════════════════════════════
# T4 — Clarification flow: vague request → needs_input (NOT workflow_ready)
# ════════════════════════════════════════════════════════════════════
heading "T4 — Clarification (ambiguous request, LLM must ask rather than guess)"

F="$(chat_stream t4 60 "Analyze my biological data")"
STATE="$(sse_final_field "$F" "state")"
note "  state: $STATE"
# Should NOT immediately return workflow_ready — needs more info from user
expect "vague request does NOT immediately trigger workflow_ready" \
  "${STATE:-needs_input}" "^(needs_input|chat_only|workflow_failed)$"

# ════════════════════════════════════════════════════════════════════
# T5 — Workflow structure: name + domain present, no "undefined" strings
# ════════════════════════════════════════════════════════════════════
heading "T5 — Workflow JSON structure (reuses T3 output)"

WF_DOMAIN="$(sse_final_field "$TMP_DIR/t3.sse" "workflow.workflow_ga.domain")"
WF_DESC="$(sse_final_field "$TMP_DIR/t3.sse" "workflow.workflow_ga.description")"
note "  domain: $WF_DOMAIN"
note "  description (first 80): $(echo "$WF_DESC" | head -c 80)"

expect "workflow.domain is present" "${WF_DOMAIN:-}" "^.{3,}$" "P1"
# Check raw SSE stream for any "undefined" values in workflow JSON block
UNDEF_COUNT="$(grep '"workflow"' "$TMP_DIR/t3.sse" 2>/dev/null \
  | grep -c '"undefined"' 2>/dev/null || echo 0)"
expect "workflow JSON contains no literal \"undefined\" values" \
  "${UNDEF_COUNT}" "^0$"

# ════════════════════════════════════════════════════════════════════
# T6 — Domain routing: ADMET → drug_discovery domain
# ════════════════════════════════════════════════════════════════════
heading "T6 — Domain routing (ADMET request → drug_discovery)"

F="$(chat_stream t6 120 \
  "Screen these SMILES for ADMET properties: CC(=O)Oc1ccccc1C(=O)O, c1ccc(cc1)N. I need hERG, Caco-2, and LogP predictions.")"
STATE="$(sse_final_field "$F" "state")"
WF_DOMAIN="$(sse_final_field "$F" "workflow.workflow_ga.domain")"
WF_NAME="$(sse_final_field "$F" "workflow.workflow_ga.name")"
note "  state: $STATE  |  domain: $WF_DOMAIN  |  name: $WF_NAME"

expect "ADMET request resolves to a workflow" "${STATE:-}" "^workflow_ready$" "P1"
expect "domain is drug_discovery" \
  "${WF_DOMAIN:-}" "^drug_discovery$" "P1"

# ════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════
printf "\n${C_WARN}═══ Provider Compatibility Summary ═══${C_RESET}\n" | tee -a "$RUN_LOG"
printf "  target:   %s\n" "$BIOMATE_URL" | tee -a "$RUN_LOG"
printf "  passes:   %d\n" "$PASS_COUNT"  | tee -a "$RUN_LOG"
printf "  P0 fails: %s%d%s\n" "$([[ $P0_FAILS -gt 0 ]] && echo "$C_FAIL" || echo "$C_OK")" \
  "$P0_FAILS" "$C_RESET" | tee -a "$RUN_LOG"
printf "  P1 fails: %d\n" "$P1_FAILS"   | tee -a "$RUN_LOG"
printf "  log:      %s\n" "$RUN_LOG"    | tee -a "$RUN_LOG"

if [ "$P0_FAILS" -gt 0 ]; then
  printf "\n${C_FAIL}FAIL — %d P0 failure(s). Provider is NOT compatible.${C_RESET}\n" \
    "$P0_FAILS" | tee -a "$RUN_LOG"
  exit 1
else
  printf "\n${C_OK}PASS — provider is compatible with BioMate's required response patterns.${C_RESET}\n" \
    | tee -a "$RUN_LOG"
  exit 0
fi
