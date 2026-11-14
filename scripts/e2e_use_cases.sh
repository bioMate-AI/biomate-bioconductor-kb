#!/usr/bin/env bash
# e2e_use_cases.sh — consolidated HTTP-level e2e for the canonical
# fixture user. Two flows total:
#
#   FLOW A (one login + one project) — exercises everything that
#          needs an authenticated context: chat-stream behaviours,
#          gate decisions, dataset cap, compression UUID preservation,
#          microarray routing, episode write path. Mirrors the
#          journey of a real session, not isolated micro-tests.
#
#   FLOW B (no-auth probes) — POST /api/projects without a token →
#          401; GET fake-uuid with the fixture's token → 404. No
#          login required; runs in seconds.
#
# Per CLAUDE.md:
#   - Single canonical fixture lifeifei163361@163.com
#   - NEVER call /api/auth/register
#   - Reuse one login + one project for everything below
#
# Default target dev; override with BIOMATE_URL=…
# Per-run log in docs/e2e_runs/<TS>.log.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO/docs/e2e_runs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="$LOG_DIR/${TS}.log"

BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"
FIXTURE_EMAIL="${FIXTURE_EMAIL:-lifeifei163361@163.com}"
FIXTURE_PASSWORD="${FIXTURE_PASSWORD:-WpmFixture!2026}"

C_OK=$'\033[32m'   ; C_FAIL=$'\033[31m'
C_WARN=$'\033[33m' ; C_DIM=$'\033[2m'  ; C_RESET=$'\033[0m'

P0_FAILS=0 ; P1_FAILS=0 ; P2_FAILS=0 ; PASS_COUNT=0 ; ACTIVE_P="P0"

heading() { printf "\n${C_WARN}── %s ──${C_RESET}\n" "$*" | tee -a "$RUN_LOG"; }
note()    { printf "%s\n" "$*" | tee -a "$RUN_LOG"; }
expect()  {
  local desc="$1" actual="$2" expected="$3" prio="${4:-$ACTIVE_P}"
  if echo "$actual" | grep -qE -- "$expected"; then
    printf "  ${C_OK}✓${C_RESET} %s\n" "$desc" | tee -a "$RUN_LOG"
    PASS_COUNT=$((PASS_COUNT+1))
    return 0
  else
    printf "  ${C_FAIL}✗${C_RESET} %s\n      expected: %s\n      got:      %s\n" \
      "$desc" "$expected" "$(echo "$actual" | head -c 200)" | tee -a "$RUN_LOG"
    case "$prio" in
      P0) P0_FAILS=$((P0_FAILS+1)) ;;
      P1) P1_FAILS=$((P1_FAILS+1)) ;;
      P2) P2_FAILS=$((P2_FAILS+1)) ;;
    esac
    return 1
  fi
}

POST() {
  curl -sS -X POST "$BIOMATE_URL$1" \
    ${2:+-H "Authorization: Bearer $2"} \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    -H "content-type: application/json" \
    --max-time "${TIMEOUT:-30}" -d "${3:-}" 2>&1
}
GET() {
  curl -sS "$BIOMATE_URL$1" \
    ${2:+-H "Authorization: Bearer $2"} \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    --max-time "${TIMEOUT:-15}" 2>&1
}
DEL() {
  curl -sS -X DELETE "$BIOMATE_URL$1" \
    ${2:+-H "Authorization: Bearer $2"} \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    --max-time "${TIMEOUT:-15}" 2>&1
}
STATUS() {
  curl -sS -o /dev/null -w "%{http_code}" -X "$1" "$BIOMATE_URL$2" \
    ${3:+-H "Authorization: Bearer $3"} \
    -H "x-e2e-test-token: $E2E_TEST_TOKEN" \
    --max-time "${TIMEOUT:-15}"
}

json() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); ks='''$1'''.split('.'); v=d
for k in ks:
  if isinstance(v, list): v = v[int(k)] if k.isdigit() else None
  elif isinstance(v, dict): v = v.get(k)
  else: v = None
print('' if v is None else (json.dumps(v) if isinstance(v,(dict,list)) else str(v)))"; }

note "${C_DIM}target:  $BIOMATE_URL${C_RESET}"
note "${C_DIM}log:     $RUN_LOG${C_RESET}"
note "${C_DIM}fixture: $FIXTURE_EMAIL (single canonical, per CLAUDE.md)${C_RESET}"

# ════════════════════════════════════════════════════════════════════
#                     FLOW A — one login, one project
# ════════════════════════════════════════════════════════════════════
heading "Flow A — login fixture + create project + sequential scenarios"
ACTIVE_P="P0"

LOGIN_RESP="$(POST /api/auth/login "" \
  "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\"}")"
JWT="$(echo "$LOGIN_RESP" | json token)"
expect "fixture login OK (no register)" "${#JWT}" "^[1-9][0-9]{2,}$"

P_CREATE="$(POST /api/projects "$JWT" \
  '{"name":"e2e-flowA","primaryDomain":"transcriptomics"}')"
PID="$(echo "$P_CREATE" | json project.id)"
expect "POST /api/projects returns uuid" "$PID" "^[0-9a-f-]{36}$"

# Trap to clean up the project on any exit (success or failure)
cleanup() { [ -n "${PID:-}" ] && DEL "/api/projects/$PID" "$JWT" > /dev/null 2>&1 || true; }
trap cleanup EXIT

# ── A1 — chat ready+final on a vanilla "hello" ──────────────────────
note ""
note "  A1 — chat-stream baseline (hello)"
SESS="flowA-hello-$(date +%s)"
TIMEOUT=45 POST /api/chat/stream "$JWT" \
  "{\"message\":\"hello\",\"stream\":true,\"context\":{\"sessionId\":\"$SESS\",\"projectId\":\"$PID\",\"previousMessages\":[]}}" \
  | grep -oE "event: [a-z_]+" | sort -u > "$LOG_DIR/${TS}_a1_events"
expect "chat-stream emits ready+final" \
       "$(tr '\n' ' ' < "$LOG_DIR/${TS}_a1_events")" "ready.*final|final.*ready"

# ── A2 — microarray DEG routes to limma (workflow_ready + 'limma') ──
note ""
note "  A2 — microarray DEG routes to limma (90s LLM budget)"
SESS="flowA-deg-$(date +%s)"
TIMEOUT=90 POST /api/chat/stream "$JWT" \
  "{\"message\":\"Run DEG on the gse22055 microarray with limma, tumor vs normal\",\"stream\":true,\"context\":{\"sessionId\":\"$SESS\",\"projectId\":\"$PID\",\"previousMessages\":[]}}" \
  > "$LOG_DIR/${TS}_a2_stream"
expect "workflow_ready event emitted" \
       "$(grep -oE 'workflow_(ready|failed)' "$LOG_DIR/${TS}_a2_stream" | head -1)" "^workflow_ready$"
expect "'limma' mentioned in response (microarray-aware routing)" \
       "$(grep -ciE 'limma' "$LOG_DIR/${TS}_a2_stream" || true)" "^[1-9][0-9]*$"

# ── A3 — gate skips on pure-knowledge question ──────────────────────
ACTIVE_P="P1"
note ""
note "  A3 — pure-knowledge question (BH FDR) routes chat_only/needs_input/workflow_failed"
SESS="flowA-bh-$(date +%s)"
RESP="$(TIMEOUT=45 POST /api/chat/stream "$JWT" \
  "{\"message\":\"What is BH FDR correction in differential expression?\",\"stream\":true,\"context\":{\"sessionId\":\"$SESS\",\"previousMessages\":[]}}")"
expect "abstract question → not workflow_ready" \
       "$(echo "$RESP" | grep -oE '"state":"[a-z_]+"' | head -1)" \
       "chat_only|workflow_failed|needs_input"

# ── A4 — dataset cap enforced on POST /api/sessions (33 → 32) ───────
note ""
note "  A4 — dataset cap (POST /api/sessions, 33 in → server keeps 32, oldest dropped)"
SESSC="flowA-cap-$(date +%s)"
DATASETS_JSON="$(python3 -c "
import json
arr = [{'id': f'ds-{i:03d}', 'name': f'file{i:03d}.csv', 'type': 'csv'} for i in range(33)]
print(json.dumps(arr))")"
RESP="$(POST /api/sessions "$JWT" \
  "{\"session_id\":\"$SESSC\",\"datasets\":$DATASETS_JSON,\"messages\":[]}")"
PERSIST_LEN="$(echo "$RESP" | json datasets | python3 -c 'import sys,json; print(len(json.loads(sys.stdin.read())))' 2>/dev/null || true)"
expect "server kept ≤ 32 entries" "$PERSIST_LEN" "^(3[0-2]|[12][0-9]|[1-9])$"
expect "first kept = ds-001 (oldest dropped)" \
       "$(echo "$RESP" | json datasets | python3 -c 'import sys,json; d=json.loads(sys.stdin.read()); print(d[0].get("id","") if d else "")' 2>/dev/null || true)" \
       "^ds-001$"
DEL "/api/sessions/$SESSC" "$JWT" > /dev/null 2>&1 || true

# ── A5 — compression preserves dataset UUIDs verbatim ───────────────
note ""
note "  A5 — compression UUID preservation"
PAYLOAD="$(python3 - <<'PY'
import json
msgs = []
msgs.append({"id":"m0","role":"user",
             "content":"[Galaxy dataset: pinned.csv (id: deadbeef-1234-cafe-babe-0000-uuid)] tumor vs normal",
             "timestamp":"2026-06-14T00:00:00Z"})
for i in range(1, 30):
  role = "user" if i%2==0 else "assistant"
  text = (f"User question {i} about DEG analysis." if role=="user"
          else f"BioMate response about counts, dispersion, BH FDR, and design matrix considerations. " * 10)
  msgs.append({"id":f"m{i}","role":role,"content":text,"timestamp":"2026-06-14T00:00:00Z"})
print(json.dumps({"sessionId":"flowA-comp","messages":msgs,"keepRecentCount":3}))
PY
)"
TIMEOUT=120 RESP="$(POST /api/compress-session "$JWT" "$PAYLOAD")"
SUMSG="$(echo "$RESP" | python3 -c '
import sys,json
r=json.loads(sys.stdin.read())
sm=next((m for m in r.get("compressedMessages",[]) if "Summary" in m.get("content","")), None)
print(sm["content"] if sm else "")
' 2>/dev/null || true)"
expect "summary preserves the dataset UUID verbatim" \
       "$(echo "$SUMSG" | grep -c 'deadbeef-1234-cafe-babe-0000-uuid' || true)" "^[1-9]"
expect "'Preserved dataset attachments' header in summary" \
       "$(echo "$SUMSG" | grep -c 'Preserved dataset attachments' || true)" "^[1-9]"

# ── A6 — Bioc routing returns workflow_state for 3 domain prompts ───
note ""
note "  A6 — Bioc routing (proteomics / microbiome / cryoEM)"
for q in "MS proteomics differential abundance" \
         "phyloseq microbiome differential analysis" \
         "GPCR cryo-EM density map reconstruction"; do
  S="flowA-route-$(date +%s%N)"
  R="$(TIMEOUT=90 POST /api/chat/stream "$JWT" \
    "{\"message\":\"$q\",\"stream\":true,\"context\":{\"sessionId\":\"$S\",\"projectId\":\"$PID\",\"previousMessages\":[]}}")"
  ST="$(echo "$R" | grep -oE '"state":"[a-z_]+"' | head -1)"
  expect "  '$q' → workflow/chat/needs_input state" "$ST" "workflow|chat|needs_input"
done

# ════════════════════════════════════════════════════════════════════
#         FLOW B — no-auth and fake-uuid (no login needed)
# ════════════════════════════════════════════════════════════════════
ACTIVE_P="P0"
heading "Flow B — auth + ownership gates (no second user needed)"
expect "GET no-auth → 401"   "$(STATUS GET    /api/projects)"        "^401$"
expect "POST no-auth → 401"  "$(STATUS POST   /api/projects)"        "^401$"
expect "GET fake-uuid auth → 404 (not 403)" \
       "$(STATUS GET /api/projects/00000000-0000-0000-0000-000000000000 "$JWT")" "^404$"
expect "branch self-check (CLAUDE.md sync rule)" \
       "$(cd "$REPO" && git branch --show-current 2>/dev/null || echo '?')" \
       "^integration/next-phase$"

note ""
note "${C_DIM}Coverage note: full cross-user 7-assertion matrix is in"
note "${C_DIM}scripts/audit_project_framework.sh (S3). UI flows (UC-11 chain↔chat,"
note "${C_DIM}UC-12 schema extraction) are Playwright; UC-13 memory failure"
note "${C_DIM}injection is server/chat-audit-followups.test.ts. UC-8 expired-trial"
note "${C_DIM}requires SQL UPDATE — covered by audit_project_framework.sh.${C_RESET}"

# ════════════════════════════════════════════════════════════════════
#                              Summary
# ════════════════════════════════════════════════════════════════════
printf "\n${C_WARN}═══ Summary ═══${C_RESET}\n" | tee -a "$RUN_LOG"
printf "  passes:   %d\n" "$PASS_COUNT" | tee -a "$RUN_LOG"
printf "  P0 fails: %s\n" "$P0_FAILS"   | tee -a "$RUN_LOG"
printf "  P1 fails: %s\n" "$P1_FAILS"   | tee -a "$RUN_LOG"
printf "  P2 fails: %s\n" "$P2_FAILS"   | tee -a "$RUN_LOG"
printf "  log:      %s\n" "$RUN_LOG"    | tee -a "$RUN_LOG"

if [[ "$P0_FAILS" -gt 0 ]]; then
  printf "${C_FAIL}✗ P0 fail — do NOT sync${C_RESET}\n" | tee -a "$RUN_LOG"
  exit 2
fi
if [[ "$P1_FAILS" -gt 0 ]]; then
  printf "${C_WARN}⚠ P1 fail(s) — sync still possible but file a release note${C_RESET}\n" | tee -a "$RUN_LOG"
  exit 1
fi
printf "${C_OK}✓ all P0+P1 scenarios green${C_RESET}\n" | tee -a "$RUN_LOG"
exit 0
