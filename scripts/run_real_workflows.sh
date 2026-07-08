#!/usr/bin/env bash
# run_real_workflows.sh — reproducible REAL workflow-execution harness.
#
# Runs the 4 canonical real-run Playwright e2e suites SEQUENTIALLY against
# dev (NEXTFLOW_USE_AWS=true → real AWS Batch, mock_mode=false → real data),
# each polling its run to a terminal state (completed | failed). Collects
# run_id + pass/fail per domain and prints a summary.
#
# This is NOT a mock/demo harness. Each domain launches a real Nextflow run
# on AWS Batch and costs real money + wall-clock:
#   ADMET/RNA-seq  ~$0.05–0.20, 3–12 min each
#   WGS (germline) ~$0.20–0.50, 8–15 min
#   CryoEM (GPU)   ~$1.50,      ~35 min
# Full sweep ≈ $2 and ~60–75 min. Run a subset with DOMAINS=... to save cost.
#
# Usage:
#   E2E_FIXTURE_PASSWORD=... scripts/run_real_workflows.sh                 # all 4
#   DOMAINS="admet rnaseq" E2E_FIXTURE_PASSWORD=... scripts/run_real_workflows.sh
#   BIOMATE_URL=https://dev-public.biomate.ai ... (override target)
#
# Per CLAUDE.md: single canonical fixture, dev target, no mocks.
# NOTE: written for bash 3.2 (macOS default) — no associative arrays.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FE="$REPO/frontend"
LOG_DIR="$REPO/docs/real_run_harness"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
SUMMARY="$LOG_DIR/${TS}_summary.txt"

export BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
export E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"
export E2E_FIXTURE_PASSWORD="${E2E_FIXTURE_PASSWORD:-}"

C_OK=$'\033[32m'; C_FAIL=$'\033[31m'; C_WARN=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'

# domain -> e2e spec file (bash-3.2-safe: a case, not an assoc array)
spec_for() {
  case "$1" in
    admet)  echo "e2e/drug-discovery-full-e2e.e2e.ts" ;;
    rnaseq) echo "e2e/complete-workflow.e2e.ts" ;;
    wgs)    echo "e2e/germline-complete-e2e.e2e.ts" ;;
    cryoem) echo "e2e/cryoem-real-e2e.e2e.ts" ;;
    *)      echo "" ;;
  esac
}
ORDER="admet rnaseq wgs cryoem"          # cheapest → most expensive
DOMAINS="${DOMAINS:-$ORDER}"

printf "${C_DIM}target : %s\n" "$BIOMATE_URL" | tee "$SUMMARY"
printf "domains: %s\n" "$DOMAINS" | tee -a "$SUMMARY"
printf "log dir: %s${C_RST}\n\n" "$LOG_DIR" | tee -a "$SUMMARY"

if [ -z "$E2E_FIXTURE_PASSWORD" ]; then
  printf "${C_WARN}⚠  E2E_FIXTURE_PASSWORD is unset — tests that log in will fail.${C_RST}\n"
  printf "   export it first (do NOT commit it). Aborting.\n"
  exit 2
fi

cd "$FE" || exit 1
FAILS=0
RESULTS=""   # accumulated "domain|result|run_id" lines for the summary
for d in $DOMAINS; do
  spec="$(spec_for "$d")"
  if [ -z "$spec" ]; then printf "${C_WARN}skip unknown domain: %s${C_RST}\n" "$d"; continue; fi
  log="$LOG_DIR/${TS}_${d}.log"
  printf "${C_WARN}── %s → %s ──${C_RST}\n" "$d" "$spec" | tee -a "$SUMMARY"

  npx playwright test "$spec" --project chromium --retries=0 --reporter=line 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}

  # Best-effort run_id extraction from the test's own logging.
  rid="$(grep -hoiE "run[_ ]?id[\": =]+[0-9a-f-]{36}" "$log" | grep -oE "[0-9a-f-]{36}" | head -1)"
  [ -n "$rid" ] || rid="—"
  if [ "$rc" -eq 0 ]; then res="PASS"; else res="FAIL(rc=$rc)"; FAILS=$((FAILS+1)); fi
  RESULTS="${RESULTS}${d}|${res}|${rid}"$'\n'
  printf "  → %s  run_id=%s\n\n" "$res" "$rid" | tee -a "$SUMMARY"
done

printf "\n${C_WARN}════ SUMMARY ════${C_RST}\n" | tee -a "$SUMMARY"
printf "%s" "$RESULTS" | while IFS='|' read -r d res rid; do
  [ -n "$d" ] || continue
  case "$res" in PASS) c=$C_OK;; *) c=$C_FAIL;; esac
  printf "  ${c}%-8s %-12s${C_RST} run_id=%s\n" "$d" "$res" "$rid" | tee -a "$SUMMARY"
done
printf "\n%s\n" "$([ "$FAILS" -eq 0 ] && echo "${C_OK}ALL GREEN${C_RST}" || echo "${C_FAIL}${FAILS} domain(s) failed${C_RST}")" | tee -a "$SUMMARY"
exit "$FAILS"
