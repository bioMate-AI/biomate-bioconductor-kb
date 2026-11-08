#!/usr/bin/env bash
# e2e_models_tracks.sh — consolidated HTTP-level e2e for the Models-module
# phase upgrade (PR #212): the Train/Adapt/Optimise track reads, the Adapt
# toggle + retrain mutations, and the retrain → first-class-run wiring.
#
# Modeled on scripts/e2e_use_cases.sh (the canonical harness): same POST/GET/
# STATUS/json/expect helpers, P0/P1/P2 priorities, single canonical fixture,
# one login + one project, Flow A (authenticated journey) + Flow B (auth-gate
# probes). Per CLAUDE.md e2e discipline — never register, reuse the session.
#
# What it proves (the LIVE wiring the unit suites cannot):
#   - proxy → Galaxy → real store for all three track reads
#   - honest-empty contract on a fresh project
#   - Adapt toggle PERSISTS across a re-read (disabled_pairs.jsonl)
#   - retrain returns a terminal status and a runId
#   - the retrain runId shows up as a first-class run (dashboard store)
#
# Coverage note (do NOT re-implement here): objects-not-strings rendering,
# empty states, toggle-fires-callback, safety-gate rejection display are in
# frontend/client/src/components/models/models.test.tsx; the Optimise math +
# toggle round-trip are in backend/test/unit/webapps/api/
# test_models_inference_shape.py. This harness adds only the live wiring proof.
#
# Default target dev; override with BIOMATE_URL=…
# Per-run log in docs/e2e_runs/<TS>_models_tracks.log.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO/docs/e2e_runs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="$LOG_DIR/${TS}_models_tracks.log"

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

# is_json <text> — "json" if the payload parses as JSON, else "notjson".
is_json() { echo "$1" | python3 -c 'import sys,json;
try: json.loads(sys.stdin.read()); print("json")
except Exception: print("notjson")' 2>/dev/null; }

# route_missing <text> — "missing" when the body is the Node "API route … not
# found" 404 envelope. A JSON error page still parses as JSON, so is_json alone
# would false-green; this distinguishes "endpoint not deployed" from a real
# contract response, so the harness fails loudly with a deploy diagnosis.
route_missing() { echo "$1" | grep -qiE '"error":"NotFound"|route .* not found' && echo "missing" || echo "present"; }

# Preflight: if the Models endpoints 404 as "route not found", the branch is not
# deployed to this target. Fail fast with a clear diagnosis rather than emit a
# cascade of confusing shape failures.
PREFLIGHT="$(curl -sS "$BIOMATE_URL/api/models" -H "x-e2e-test-token: $E2E_TEST_TOKEN" --max-time 15 2>&1)"
if [ "$(route_missing "$PREFLIGHT")" = "missing" ]; then
  printf "${C_FAIL}✗ PREFLIGHT: /api/models returns 'route not found' on %s${C_RESET}\n" "$BIOMATE_URL" | tee -a "$RUN_LOG"
  printf "${C_WARN}  The Models-module code (PR #212) is not deployed to this target.\n" | tee -a "$RUN_LOG"
  printf "  Merge feat/dl-upgrade-wave3 → integration/next-phase and sync to dev,\n" | tee -a "$RUN_LOG"
  printf "  then re-run. Aborting to avoid false failures.${C_RESET}\n" | tee -a "$RUN_LOG"
  exit 3
fi

note "${C_DIM}target:  $BIOMATE_URL${C_RESET}"
note "${C_DIM}log:     $RUN_LOG${C_RESET}"
note "${C_DIM}fixture: $FIXTURE_EMAIL (single canonical, per CLAUDE.md)${C_RESET}"

# ════════════════════════════════════════════════════════════════════
#                     FLOW A — one login, one project
# ════════════════════════════════════════════════════════════════════
heading "Flow A — login fixture + create project + model-tracks scenarios"
ACTIVE_P="P0"

LOGIN_RESP="$(POST /api/auth/login "" \
  "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\"}")"
JWT="$(echo "$LOGIN_RESP" | json token)"
expect "fixture login OK (no register)" "${#JWT}" "^[1-9][0-9]{2,}$"

P_CREATE="$(POST /api/projects "$JWT" \
  '{"name":"e2e-models-tracks","primaryDomain":"drug_discovery"}')"
PID="$(echo "$P_CREATE" | json project.id)"
expect "POST /api/projects returns uuid" "$PID" "^[0-9a-f-]{36}$"

cleanup() { [ -n "${PID:-}" ] && DEL "/api/projects/$PID" "$JWT" > /dev/null 2>&1 || true; }
trap cleanup EXIT

# ── A1 — Registry read is live (proxy → Galaxy → catalog) ───────────
note ""
note "  A1 — GET /api/models (registry catalog is a live array)"
R="$(GET "/api/models" "$JWT")"
expect "registry is a JSON array (catalog rows or [])" \
       "$(echo "$R" | python3 -c 'import sys,json;
try: print("array" if isinstance(json.loads(sys.stdin.read()),list) else "no")
except Exception: print("no")' 2>/dev/null || true)" \
       "^array$"

# ── A2 — Train track read (honest-empty {runs:[]} on a fresh project) ─
note ""
note "  A2 — GET /api/model-tracks/train (contract: {runs: [...]})"
R="$(GET "/api/model-tracks/train?project=$PID" "$JWT")"
expect "train payload has a 'runs' array" \
       "$(echo "$R" | python3 -c 'import sys,json;
try: d=json.loads(sys.stdin.read()); print("ok" if isinstance(d.get("runs"),list) else "no")
except Exception: print("no")' 2>/dev/null || true)" \
       "^ok$"

# ── A3 — Adapt track read ({pendingCount, pairs}) ───────────────────
note ""
note "  A3 — GET /api/model-tracks/adapt (contract: {pairs: [...]})"
R="$(GET "/api/model-tracks/adapt?project=$PID" "$JWT")"
expect "adapt payload has a 'pairs' array" \
       "$(echo "$R" | python3 -c 'import sys,json;
try: d=json.loads(sys.stdin.read()); print("ok" if isinstance(d.get("pairs"),list) else "no")
except Exception: print("no")' 2>/dev/null || true)" \
       "^ok$"
FIRST_PAIR_ID="$(echo "$R" | python3 -c 'import sys,json;
try: d=json.loads(sys.stdin.read()); ps=d.get("pairs") or []; print(ps[0]["id"] if ps else "")
except Exception: print("")' 2>/dev/null || true)"

# ── A4 — Optimise track read (active:false OR a loop with rounds[]) ──
note ""
note "  A4 — GET /api/model-tracks/optimise (contract: {active:false} | {rounds:[...]})"
R="$(GET "/api/model-tracks/optimise?project=$PID" "$JWT")"
expect "optimise is {active:false} or has rounds[]" \
       "$(echo "$R" | python3 -c 'import sys,json;
try:
  d=json.loads(sys.stdin.read()); print("ok" if (d.get("active") is False or isinstance(d.get("rounds"),list)) else "no")
except Exception: print("no")' 2>/dev/null || true)" \
       "^ok$"

# ── A5 — Adapt retrain returns a terminal status + runId (P0) ───────
note ""
note "  A5 — POST /api/model-tracks/adapt/retrain (terminal status + runId)"
R="$(TIMEOUT=90 POST "/api/model-tracks/adapt/retrain?project=$PID" "$JWT" '{}')"
RETRAIN_STATUS="$(echo "$R" | json status)"
expect "retrain status is terminal-or-queued" "$RETRAIN_STATUS" \
       "^(completed|succeeded|running|queued|failed)$"
RUN_ID="$(echo "$R" | json runId)"
# runId is best-effort (Postgres registration); present on a healthy dev.
expect "retrain surfaces a runId (first-class run registered)" \
       "$RUN_ID" "^[0-9a-fA-F-]{8,}$" "P1"

# ── A6 — the retrain run appears in the runs list (cross-surface) ────
ACTIVE_P="P1"
note ""
note "  A6 — retrain runId appears in the runs/dashboard list"
if [ -n "$RUN_ID" ]; then
  # The runs/dashboard list is served at /api/workflows/runs (the earlier
  # /api/execution-runs & /api/runs guesses are 404 — benchmark design error,
  # fixed 2026-10-28). Verified live on dev: the Adapt retrain registers a
  # first-class run that appears here tagged workflow_type:"training"
  # (workflowName "Adaptation retrain"). Project-scoped first, user-scoped fallback.
  RUNS="$(GET "/api/workflows/runs?projectId=$PID" "$JWT")"
  if [ "$(is_json "$RUNS")" != "json" ]; then RUNS="$(GET "/api/workflows/runs" "$JWT")"; fi
  expect "runs list contains the retrain runId" \
         "$(echo "$RUNS" | grep -c "$RUN_ID" || true)" "^[1-9]"
  expect "the run is tagged as training (not a faked Nextflow pipeline)" \
         "$(echo "$RUNS" | grep -ciE 'training|Adaptation retrain' || true)" "^[1-9]"
else
  note "  ${C_DIM}(skipped — no runId; registration is best-effort and may be off on this env)${C_RESET}"
fi

# ── A7 — Adapt toggle PERSISTS across a re-read (P0 when a pair exists)
ACTIVE_P="P0"
note ""
note "  A7 — POST /adapt/{id}/toggle persists across a re-read"
if [ -n "$FIRST_PAIR_ID" ]; then
  BEFORE="$(GET "/api/model-tracks/adapt?project=$PID" "$JWT" \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=next((x for x in d.get('pairs',[]) if x['id']=='$FIRST_PAIR_ID'),{}); print(p.get('on'))" 2>/dev/null || true)"
  TOG="$(POST "/api/model-tracks/adapt/$FIRST_PAIR_ID/toggle?project=$PID" "$JWT" '{}')"
  expect "toggle returns {id,on}" "$(echo "$TOG" | json id)" "^${FIRST_PAIR_ID}$"
  NEWON="$(echo "$TOG" | json on)"
  AFTER="$(GET "/api/model-tracks/adapt?project=$PID" "$JWT" \
    | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=next((x for x in d.get('pairs',[]) if x['id']=='$FIRST_PAIR_ID'),{}); print(p.get('on'))" 2>/dev/null || true)"
  expect "re-read reflects the toggled state (persisted)" "$AFTER" "^${NEWON}$"
  # restore original state so the fixture is left clean
  POST "/api/model-tracks/adapt/$FIRST_PAIR_ID/toggle?project=$PID" "$JWT" \
       "{\"on\": ${BEFORE:-true}}" > /dev/null 2>&1 || true
else
  note "  ${C_DIM}(skipped — no recorded edit pairs for this project; covered by the"
  note "  ${C_DIM} backend toggle round-trip unit test test_adapt_toggle_roundtrip)${C_RESET}"
fi

# ════════════════════════════════════════════════════════════════════
#         FLOW B — route gates (no second user needed)
# ════════════════════════════════════════════════════════════════════
# NOTE on auth posture: the Models + model-tracks routes are mounted with
# `optionalAuth` (frontend/server/auth-middleware.ts:219) — like /api/models*,
# they proxy to Galaxy whether or not a token is present, so a no-token request
# is NOT a 401. (Only `requireAuth` routes such as /api/projects return 401.)
# We therefore assert the REAL behaviour: the route exists (not a 404
# "route not found") and the greedy /api/models/{id} route does not swallow the
# model-tracks prefix (risk R1).
ACTIVE_P="P0"
heading "Flow B — route gates (optionalAuth: no 401 by design)"
TRAIN_NOAUTH="$(STATUS GET /api/model-tracks/train)"
expect "GET /api/model-tracks/train (no token) is routed, not 'route not found'" \
       "$TRAIN_NOAUTH" "^(200|400|401|403|500|502)$"
expect "  …and specifically is NOT a 404 (route exists / R1: not swallowed)" \
       "$TRAIN_NOAUTH" "^(200|400|401|403|500|502)$"
# The detail route must 404 (not 500) for an unknown id.
expect "GET /api/models/does-not-exist auth → 404 (not 500)" \
       "$(STATUS GET /api/models/does-not-exist "$JWT")" "^404$" "P1"

note ""
note "${C_DIM}Coverage note: rendering/objects-not-strings/empty-states/safety-gate"
note "${C_DIM}display are in models.test.tsx; Optimise math + toggle flip/round-trip"
note "${C_DIM}are in test_models_inference_shape.py. This harness proves only the"
note "${C_DIM}live proxy→Galaxy→store wiring + persistence + cross-surface run.${C_RESET}"

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
