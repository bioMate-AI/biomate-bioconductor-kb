#!/usr/bin/env bash
# e2e_data_centric.sh — consolidated HTTP-level E2E for the data-centric
# upgrade (feat/data-centric-upgrade). Exercises EVERY new user-facing API
# surface end-to-end through the Node proxy → Galaxy backend on dev.
#
# ── What is new in this upgrade (all proxied in frontend/server/routes.ts,
#    all `optionalAuth`, all backed by Galaxy FastAPI routers) ──────────────
#   Models module   backend/.../api/models_inference.py
#     GET  /api/models                        registry list (JSON array)
#     GET  /api/models/{id}                    model object (identity/evidence/…)
#     POST /api/models/{id}/infer              submit inference → {run_id}
#     GET  /api/inference/{run_id}/result      poll → running|completed|failed
#     GET  /api/model-tracks/train             Train track → {runs:[…]}
#     GET  /api/model-tracks/adapt             Adapt track → {pendingCount,pairs}
#     GET  /api/model-tracks/optimise          Optimise/DMTA → {active:…}
#     POST /api/model-tracks/adapt/retrain     retrain → {…}
#   Design & Generate  backend/.../api/generation.py
#     POST /api/generate                       launch run → {run_id,status}
#     GET  /api/generate/{run_id}              poll de-novo design run
#   Data surfaces
#     POST /api/perception/profile             backend/.../api/perception.py
#     GET  /api/datasets/{ref}/lineage         backend/.../api/datasets_object.py
#     GET  /api/datasets/{ref}/consumers        "
#     GET  /api/datasets/{ref}/versions         "
#   Nextflow panel
#     GET  /api/nextflow/skip-analysis         backend/.../api/nextflow_executor.py
#
# ── Discipline (CLAUDE.md "E2E plan discipline") ──────────────────────────
#   * ONE canonical fixture (lifeifei163361@163.com), ONE login, ONE project.
#   * NEVER call /api/auth/register.
#   * Flow A = long sequential journey through the new surfaces.
#     Flow B = cheap no-auth / gate probes (proves the optionalAuth posture).
#   * 90 s LLM/dispatch timeouts for any generative path.
#   * P0/P1/P2 gating; P0 fail ⇒ exit 2 (do NOT sync), P1 ⇒ exit 1.
#   * Per-run log under docs/e2e_runs/<TS>_data_centric.log.
#
# ── route_missing PREFLIGHT ───────────────────────────────────────────────
#   These routes are NOT deployed until feat/data-centric-upgrade merges +
#   syncs. If GET /api/models does not return a JSON array (Node has no such
#   route registered → SPA index.html or 404), the harness aborts immediately
#   with a clear "merge + sync first" diagnosis and a DISTINCT exit code (3)
#   so CI can tell "not deployed" apart from a real assertion failure.
#
# ── Coverage-map discipline (what this harness does NOT re-verify) ────────
#   The React rendering of every track/panel + the react-query fetch hooks
#   are already covered by frontend/client/src/components/models/models.test.tsx
#   (mocked fetch, jsdom). The backend contract SHAPES in-process are covered
#   by backend/test/unit/webapps/api/test_models_inference_shape.py. This
#   harness intentionally does NOT re-implement either; it verifies the ONE
#   thing neither can — the LIVE WIRED PATH (browser → Node proxy → Galaxy)
#   and the real HTTP auth posture on dev. Each assertion carries a
#   `# covers:` / `# defers:` note.
#
# Default target dev; override with BIOMATE_URL=…

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO/docs/e2e_runs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="$LOG_DIR/${TS}_data_centric.log"

BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"
FIXTURE_EMAIL="${FIXTURE_EMAIL:-lifeifei163361@163.com}"
FIXTURE_PASSWORD="${FIXTURE_PASSWORD:-WpmFixture!2026}"

C_OK=$'\033[32m'   ; C_FAIL=$'\033[31m'
C_WARN=$'\033[33m' ; C_DIM=$'\033[2m'  ; C_RESET=$'\033[0m'

# Distinct exit code for "surfaces not deployed yet" so it is never confused
# with a genuine assertion failure (exit 2 = P0 fail, exit 1 = P1 fail).
EXIT_NOT_DEPLOYED=3

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
      "$desc" "$expected" "$(echo "$actual" | head -c 240)" | tee -a "$RUN_LOG"
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
    -H "content-type: application/json" \
    --max-time "${TIMEOUT:-15}"
}
# URL-encode a path segment (S3 refs / ids contain '/' and ':').
urlenc() { python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$1"; }

# json <dotpath> : read a nested value from stdin JSON (list index or dict key).
json() { python3 -c "import sys,json
try: d=json.loads(sys.stdin.read())
except Exception: print(''); sys.exit(0)
ks='''$1'''.split('.'); v=d
for k in ks:
  if isinstance(v, list): v = v[int(k)] if k.isdigit() and int(k)<len(v) else None
  elif isinstance(v, dict): v = v.get(k)
  else: v = None
print('' if v is None else (json.dumps(v) if isinstance(v,(dict,list)) else str(v)))"; }

# jhas <expr> : print 'yes' if the python expr (over parsed JSON `d`) is truthy,
# else '' — used to assert contract SHAPE, not just "is JSON".
jhas() { python3 -c "import sys,json
try: d=json.loads(sys.stdin.read())
except Exception: print(''); sys.exit(0)
try: print('yes' if ($1) else '')
except Exception: print('')"; }

note "${C_DIM}target:  $BIOMATE_URL${C_RESET}"
note "${C_DIM}log:     $RUN_LOG${C_RESET}"
note "${C_DIM}fixture: $FIXTURE_EMAIL (single canonical, per CLAUDE.md)${C_RESET}"

# ════════════════════════════════════════════════════════════════════
#  PREFLIGHT — route_missing gate (abort cleanly if not deployed)
# ════════════════════════════════════════════════════════════════════
heading "Preflight — are the data-centric routes deployed?"
# /api/models is optionalAuth (no token needed). If the branch is NOT merged
# + synced, Node has no such route → Express returns the SPA index.html (200
# text/html) or a 404 JSON. Either way it will NOT be a JSON array. We treat
# "not a JSON array" (or a 404) as not-deployed.
PRE="$(GET /api/models)"
PRE_STATUS="$(STATUS GET /api/models)"
PRE_IS_ARRAY="$(echo "$PRE" | jhas 'isinstance(d, list)')"
if [[ "$PRE_STATUS" == "404" || -z "$PRE_IS_ARRAY" ]]; then
  note ""
  note "${C_FAIL}✗ ROUTE_MISSING — /api/models did not return a JSON array.${C_RESET}"
  note "    HTTP status: $PRE_STATUS"
  note "    body (head): $(echo "$PRE" | head -c 160)"
  note ""
  note "${C_WARN}  DIAGNOSIS: the data-centric surfaces are NOT deployed on this"
  note "  target. feat/data-centric-upgrade must be MERGED into"
  note "  integration/next-phase and SYNCED to dev before this harness can run."
  note "  This is expected until the upgrade ships — it is NOT a code bug."
  note ""
  note "  Fix: merge the PR, then scripts/sync_to_dev.sh, then re-run:"
  note "       BIOMATE_URL=$BIOMATE_URL bash scripts/e2e_data_centric.sh${C_RESET}"
  note ""
  note "${C_DIM}  (exit $EXIT_NOT_DEPLOYED = not-deployed, distinct from P0/P1 fails)${C_RESET}"
  exit "$EXIT_NOT_DEPLOYED"
fi
note "  ${C_OK}✓${C_RESET} /api/models returns a JSON array — routes are live, continuing."

# ════════════════════════════════════════════════════════════════════
#  FLOW A — one login, one project, sequential journey
# ════════════════════════════════════════════════════════════════════
heading "Flow A — login fixture + create project + data-centric journey"
ACTIVE_P="P0"

LOGIN_RESP="$(POST /api/auth/login "" \
  "{\"email\":\"$FIXTURE_EMAIL\",\"password\":\"$FIXTURE_PASSWORD\"}")"
JWT="$(echo "$LOGIN_RESP" | json token)"
expect "fixture login OK (no register)" "${#JWT}" "^[1-9][0-9]{2,}$"

P_CREATE="$(POST /api/projects "$JWT" \
  '{"name":"e2e-data-centric","primaryDomain":"drug_discovery"}')"
PID="$(echo "$P_CREATE" | json project.id)"
expect "POST /api/projects returns uuid" "$PID" "^[0-9a-f-]{36}$"

cleanup() { [ -n "${PID:-}" ] && DEL "/api/projects/$PID" "$JWT" > /dev/null 2>&1 || true; }
trap cleanup EXIT

# ── A1 — Models registry list (GET /api/models) ─────────────────────
# covers:  live proxy→Galaxy catalog list; array shape; row contract keys.
# defers:  ModelsPanel Registry-track rendering → models.test.tsx.
note ""
note "  A1 — GET /api/models (registry list, contract shape)"
MODELS="$(GET /api/models "$JWT")"
expect "returns a JSON array" "$(echo "$MODELS" | jhas 'isinstance(d, list)')" "^yes$"
# Every row must carry id/name/family/version/origin (the ModelSummary contract).
# The catalog is DYNAMIC (BioNeMo rows appear only when bionemo_client exposes
# the fn; custom rows only when a campaign registered one). An empty catalog is
# an HONEST state, not a failure — so we gate the row-shape assertion on len>0.
if [[ "$(echo "$MODELS" | jhas 'len(d) > 0')" == "yes" ]]; then
  expect "each row has id+name+family+version+origin" \
    "$(echo "$MODELS" | jhas 'all(all(k in r for k in ("id","name","family","version","origin")) for r in d)')" \
    "^yes$"
  MODEL_ID="$(echo "$MODELS" | json 0.id)"
  note "  ${C_DIM}first model id: $MODEL_ID${C_RESET}"
else
  note "  ${C_WARN}⚠${C_RESET} catalog empty on this target (honest state) — infer sub-tests skipped"
  MODEL_ID=""
fi

# ── A2 — Model object detail (GET /api/models/{id}) ─────────────────
# covers:  detail contract (identity/evidence/lineage/consumers/interface/versions)
#          + unknown-id 404 + honest unevaluated verdict.
# defers:  ModelObject tab rendering + evidence-triple → models.test.tsx.
if [[ -n "$MODEL_ID" ]]; then
  note ""
  note "  A2 — GET /api/models/{id} (detail contract)"
  DETAIL="$(GET "/api/models/$(urlenc "$MODEL_ID")" "$JWT")"
  expect "detail has identity.name + evidence.gate.verdict" \
    "$(echo "$DETAIL" | jhas 'd.get("identity",{}).get("name") and "verdict" in d.get("evidence",{}).get("gate",{})')" \
    "^yes$"
  expect "detail exposes lineage+consumers+interface+versions keys" \
    "$(echo "$DETAIL" | jhas 'all(k in d for k in ("lineage","consumers","interface","versions"))')" \
    "^yes$"
  # Honesty contract: unevaluated models report a verdict string, never a
  # fabricated metric.
  expect "evidence gate verdict is a string (honest, may be not_evaluated)" \
    "$(echo "$DETAIL" | jhas 'isinstance(d["evidence"]["gate"]["verdict"], str)')" "^yes$" "P1"
  # Unknown id → 404 (not 500, not silent empty).
  expect "unknown model id → 404" \
    "$(STATUS GET /api/models/bionemo:does_not_exist "$JWT")" "^404$"
fi

# ── A3 — infer → poll (POST /api/models/{id}/infer + result) ────────
# covers:  the full submit→poll wired loop end-to-end; run_id issuance;
#          terminal-state contract of GET /api/inference/{id}/result;
#          unknown-run 404.
# defers:  InferenceResultView routing-by-evidence-class → models.test.tsx.
if [[ -n "$MODEL_ID" ]]; then
  note ""
  note "  A3 — POST infer + poll result (90s budget for a real dispatch)"
  ENC_ID="$(urlenc "$MODEL_ID")"
  # Deliberately send an empty inputs object. Structure/genomic backends raise a
  # 422/400 on missing sequence (surfaced, not masked); custom/stub backends
  # complete with a labelled stub. Either way we must get a run_id OR an honest
  # 4xx — never a 500 and never a hang.
  INFER_CODE="$(TIMEOUT=90 STATUS POST "/api/models/$ENC_ID/infer" "$JWT")"
  expect "infer returns 200 (run_id) or honest 4xx (input validation)" \
    "$INFER_CODE" "^(200|400|422)$"
  if [[ "$INFER_CODE" == "200" ]]; then
    INFER="$(TIMEOUT=90 POST "/api/models/$ENC_ID/infer" "$JWT" '{"inputs":{}}')"
    RID="$(echo "$INFER" | json run_id)"
    expect "infer response carries run_id" "$RID" "."
    if [[ -n "$RID" ]]; then
      # Poll a few times; the dispatch is synchronous server-side so it is
      # usually terminal on first read, but tolerate a couple of 'running's.
      RES=""
      for _ in 1 2 3 4 5; do
        RES="$(GET "/api/inference/$(urlenc "$RID")/result" "$JWT")"
        ST="$(echo "$RES" | json status)"
        [[ "$ST" == "completed" || "$ST" == "failed" ]] && break
        sleep 2
      done
      expect "result reaches terminal state completed|failed" \
        "$(echo "$RES" | json status)" "^(completed|failed)$"
      expect "unknown run_id → 404" \
        "$(STATUS GET /api/inference/00000000-0000-0000-0000-000000000000/result "$JWT")" "^404$" "P1"
    fi
  fi
fi

# ── A4 — Model tracks (train / adapt / optimise) ────────────────────
# covers:  live track-read contract + HONEST-EMPTY payloads for a brand-new
#          project (no training runs / DPO pairs / DMTA loop exist yet).
# defers:  Train/Adapt/Optimise track rendering + toggle callbacks →
#          models.test.tsx.
note ""
note "  A4 — model-tracks train/adapt/optimise (honest-empty on a fresh project)"
TRAIN="$(GET "/api/model-tracks/train?project=$PID" "$JWT")"
expect "train returns {runs:[…]} (array, possibly empty)" \
  "$(echo "$TRAIN" | jhas 'isinstance(d.get("runs"), list)')" "^yes$"
ADAPT="$(GET "/api/model-tracks/adapt?project=$PID" "$JWT")"
expect "adapt returns {pendingCount:int, pairs:[…]}" \
  "$(echo "$ADAPT" | jhas 'isinstance(d.get("pairs"), list) and isinstance(d.get("pendingCount"), int)')" \
  "^yes$"
OPT="$(GET "/api/model-tracks/optimise?project=$PID" "$JWT")"
# Optimise honestly returns {active:false} when no DMTA loop exists.
expect "optimise returns {active:…} (honest false for fresh project)" \
  "$(echo "$OPT" | jhas '"active" in d')" "^yes$"
expect "fresh project ⇒ optimise not active" \
  "$(echo "$OPT" | json active)" "^(false|False|)$" "P1"

# ── A5 — retrain (POST /api/model-tracks/adapt/retrain) ─────────────
# covers:  the retrain trigger returns a well-formed JSON object (not 5xx).
# defers:  the re-train button + query invalidation → models.test.tsx.
note ""
note "  A5 — POST model-tracks/adapt/retrain (well-formed, non-5xx)"
RETRAIN_CODE="$(TIMEOUT=90 STATUS POST "/api/model-tracks/adapt/retrain?project=$PID" "$JWT")"
expect "retrain returns 2xx (accepted / honest-empty), not 5xx" \
  "$RETRAIN_CODE" "^2[0-9][0-9]$" "P1"

# ── A6 — Design & Generate (POST /api/generate + poll) ──────────────
# covers:  the full de-novo generation submit→poll wired loop; run_id + status;
#          terminal-state; unknown-run 404.
# defers:  design-generate UI rendering (pareto/hit grid) → component tests.
ACTIVE_P="P1"
note ""
note "  A6 — POST /api/generate (BRICS, drug_like) + poll run"
GEN="$(TIMEOUT=90 POST /api/generate "$JWT" \
  '{"generator":"brics","objectives":["drug_like"],"count":5,"n_generate":40}')"
GRID="$(echo "$GEN" | json run_id)"
expect "generate returns run_id + status" \
  "$(echo "$GEN" | jhas 'd.get("run_id") and d.get("status")')" "^yes$"
if [[ -n "$GRID" ]]; then
  GENC=""
  for _ in $(seq 1 20); do
    GENC="$(GET "/api/generate/$(urlenc "$GRID")" "$JWT")"
    GS="$(echo "$GENC" | json status)"
    [[ "$GS" != "running" && -n "$GS" ]] && break
    sleep 3
  done
  # Accept any non-running terminal label the backend uses (it stores the run
  # dict verbatim; the frontend keys off status != 'running').
  expect "generate run reaches a terminal status (not stuck running)" \
    "$(echo "$GENC" | jhas 'd.get("status") and d.get("status") != "running"')" "^yes$" "P1"
  expect "poll unknown generate run_id → 404" \
    "$(STATUS GET /api/generate/00000000-0000-0000-0000-000000000000 "$JWT")" "^404$" "P1"
fi

# ── A7 — Perception profile (POST /api/perception/profile) ──────────
# covers:  the ingest profiler wired path + its HONEST-DEGRADE contract
#          (an unresolvable ref yields quality:'blocked' + a note, never a
#          fabricated leakage/balance number).
# defers:  DatasetObject Quality-tab rendering → component tests.
ACTIVE_P="P1"
note ""
note "  A7 — POST /api/perception/profile (honest-blocked on an unresolvable ref)"
PROF="$(POST /api/perception/profile "$JWT" \
  '{"datasetRef":"s3://biomate-nonexistent/no-such-file-e2e.csv","name":"e2e-probe"}')"
expect "profile has quality + notes[] (DataProfile contract)" \
  "$(echo "$PROF" | jhas '"quality" in d and isinstance(d.get("notes"), list)')" "^yes$"
expect "unresolvable ref ⇒ quality 'blocked' (honest, not fabricated)" \
  "$(echo "$PROF" | json quality)" "^blocked$"
expect "blocked profile carries a note explaining why" \
  "$(echo "$PROF" | jhas 'len(d.get("notes",[])) > 0')" "^yes$"
# Missing ref → still a blocked profile, never a 500.
PROF_EMPTY="$(POST /api/perception/profile "$JWT" '{}')"
expect "missing datasetRef ⇒ blocked profile (not 5xx)" \
  "$(echo "$PROF_EMPTY" | json quality)" "^blocked$" "P1"

# ── A8 — Dataset object surfaces (lineage / consumers / versions) ───
# covers:  the three data-object reads wired end-to-end + their honest-empty
#          contract for a ref with no provenance.
# defers:  DatasetObject Lineage/Consumers/Versions tab rendering → component.
note ""
note "  A8 — datasets/{ref}/{lineage,consumers,versions} (honest-empty)"
REF="$(urlenc 's3://biomate-nonexistent/no-such-e2e.csv')"
LIN="$(GET "/api/datasets/$REF/lineage" "$JWT")"
expect "lineage has ref+available+source+producedBy keys" \
  "$(echo "$LIN" | jhas 'all(k in d for k in ("ref","available","source","producedBy"))')" "^yes$"
expect "unknown ref ⇒ available:false (honest, not fabricated lineage)" \
  "$(echo "$LIN" | json available)" "^(false|False)$"
CONS="$(GET "/api/datasets/$REF/consumers" "$JWT")"
expect "consumers returns {ref, consumers:[…]}" \
  "$(echo "$CONS" | jhas 'isinstance(d.get("consumers"), list)')" "^yes$"
expect "unknown ref ⇒ empty consumers list" \
  "$(echo "$CONS" | jhas 'len(d.get("consumers",[]))==0')" "^yes$" "P1"
VERS="$(GET "/api/datasets/$REF/versions" "$JWT")"
expect "versions returns {ref, versions:[…]}" \
  "$(echo "$VERS" | jhas 'isinstance(d.get("versions"), list)')" "^yes$"

# ── A9 — Nextflow skip-analysis (GET /api/nextflow/skip-analysis) ───
# covers:  the panel's per-phase skip/dependency read wired end-to-end +
#          its 400-on-missing-param contract + {phases,count} shape.
# defers:  the SkipDependency panel rendering → nextflow-workflow-viewer tests.
ACTIVE_P="P1"
note ""
note "  A9 — GET /api/nextflow/skip-analysis ({phases,count} + 400 guard)"
# Missing nextflow_path → 400 (the Node proxy guards this before Galaxy).
expect "no nextflow_path ⇒ 400" \
  "$(STATUS GET /api/nextflow/skip-analysis "$JWT")" "^400$"
# A real workflow path → {phases:[…], count:N}. An unannotated workflow honestly
# returns phases:[] (renders nothing).
SKIP="$(GET "/api/nextflow/skip-analysis?nextflow_path=$(urlenc 'nextflow_nfcore/subworkflows/nf-core/fastq_align_bwa/main.nf')" "$JWT")"
expect "skip-analysis returns {phases:[…], count:int}" \
  "$(echo "$SKIP" | jhas 'isinstance(d.get("phases"), list) and isinstance(d.get("count"), int)')" \
  "^yes$"
# When phases are present, each must carry the SkipDependency contract keys.
if [[ "$(echo "$SKIP" | jhas 'len(d.get("phases",[]))>0')" == "yes" ]]; then
  expect "each phase has id+label+skippable" \
    "$(echo "$SKIP" | jhas 'all(all(k in p for k in ("id","label","skippable")) for p in d["phases"])')" \
    "^yes$" "P1"
fi

# ════════════════════════════════════════════════════════════════════
#  FLOW B — auth posture probes (optionalAuth: must NOT 401)
# ════════════════════════════════════════════════════════════════════
# covers:  the load-bearing posture of the new proxies — they are all
#          `optionalAuth`, so an anonymous browser (Models/Design panels
#          render pre-login) must get real data, NOT a 401. This is the
#          single most likely regression if someone "hardens" the routes.
# defers:  cross-user project ownership (404-not-403) → project-routes.test.ts
#          + scripts/audit_project_framework.sh (7-assertion S3 matrix).
ACTIVE_P="P0"
heading "Flow B — optionalAuth posture (no-token reads must NOT 401)"
expect "GET /api/models no-token → not 401 (optionalAuth)" \
  "$(STATUS GET /api/models)" "^(200|502|503)$"
expect "GET /api/model-tracks/train no-token → not 401" \
  "$(STATUS GET /api/model-tracks/train)" "^(200|502|503)$"
expect "POST /api/perception/profile no-token → not 401" \
  "$(TIMEOUT=30 STATUS POST /api/perception/profile)" "^(200|400|422|502|503)$"
expect "GET /api/nextflow/skip-analysis no-token, no param → 400 (not 401)" \
  "$(STATUS GET /api/nextflow/skip-analysis)" "^400$"
# Contrast: /api/projects IS auth-gated (proves the token wiring itself works).
expect "GET /api/projects no-token → 401 (contrast: real auth gate intact)" \
  "$(STATUS GET /api/projects)" "^401$"

note ""
note "${C_DIM}Coverage note: React rendering of every Models/Design/Datasets"
note "surface + the react-query hooks are covered by"
note "frontend/client/src/components/models/models.test.tsx (mocked fetch)."
note "Backend contract SHAPES in-process are covered by"
note "backend/test/unit/webapps/api/test_models_inference_shape.py."
note "This harness verifies ONLY the live wired path (Node proxy → Galaxy)"
note "and the HTTP auth posture on dev — the one thing those cannot.${C_RESET}"

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
printf "${C_OK}✓ all P0+P1 data-centric scenarios green${C_RESET}\n" | tee -a "$RUN_LOG"
exit 0
