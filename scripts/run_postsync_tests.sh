#!/usr/bin/env bash
# Post-sync E2E test runner — called by sync_to_dev.sh after each successful sync.
# Runs the targeted test suites against dev-public.biomate.ai and logs results.
#
# Usage: bash scripts/run_postsync_tests.sh [commit_id]
#
# Output: docs/postsync_test_results/<date>_<commit>.log
#         Exit 0 = all pass, Exit 1 = failures

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT="${1:-$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
DATE="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/docs/postsync_test_results"
LOG_FILE="$LOG_DIR/${DATE}_${COMMIT}.log"
BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
FRONTEND_DIR="$REPO_ROOT/frontend"

mkdir -p "$LOG_DIR"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }

log "=== Post-sync E2E — commit ${COMMIT} against ${BIOMATE_URL} ==="
log "Log: $LOG_FILE"

# ---------------------------------------------------------------------------
# Test suites to run (ordered fast → slow)
# ---------------------------------------------------------------------------
# Keep these FAST only — drug-discovery and germline poll AWS Batch and take
# 15–50 min each. Run them on-demand, not after every sync.
# Each entry: "label|file|timeout_ms"
SUITES=(
  "smoke-api|public-routes-smoke.e2e.ts|30000"
  "smoke-auth|auth-flows-smoke.e2e.ts|60000"
  "smoke-billing|billing-smoke.e2e.ts|60000"
  "cryo-em|cryoem-real-e2e.e2e.ts|120000"
)

PASS=0
FAIL=0
SKIP=0
RESULTS=()

cd "$FRONTEND_DIR"

for entry in "${SUITES[@]}"; do
  IFS='|' read -r label file timeout_ms <<< "$entry"
  suite_path="e2e/${file}"

  if [[ ! -f "$suite_path" ]]; then
    log "[SKIP] $label — file not found: $suite_path"
    RESULTS+=("SKIP  $label")
    ((SKIP++)) || true
    continue
  fi

  log "[RUN]  $label ($file) ..."
  suite_log="$LOG_DIR/${DATE}_${COMMIT}_${label}.log"

  if BIOMATE_URL="$BIOMATE_URL" \
       npx playwright test "$suite_path" \
         --timeout "$timeout_ms" \
         --reporter=list \
         >> "$suite_log" 2>&1; then
    # Count from Playwright summary line "N passed"
    passed=$(grep -oE "[0-9]+ passed" "$suite_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+")
    log "[PASS] $label — ${passed:-?} test(s) passed"
    RESULTS+=("PASS  $label")
    ((PASS++)) || true
  else
    # Count actual Playwright failures from summary line "N failed"
    failed=$(grep -oE "[0-9]+ failed" "$suite_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+")
    skipped=$(grep -oE "[0-9]+ skipped" "$suite_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+")
    log "[FAIL] $label — ${failed:-?} failed, ${skipped:-0} skipped — see $suite_log"
    # Print last 30 lines of suite log to main log for quick triage
    echo "--- tail: $suite_log ---" >> "$LOG_FILE"
    tail -30 "$suite_log" >> "$LOG_FILE" 2>/dev/null || true
    echo "--- end tail ---" >> "$LOG_FILE"
    RESULTS+=("FAIL  $label")
    ((FAIL++)) || true
  fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "=== Results for ${COMMIT} ==="
for r in "${RESULTS[@]}"; do
  log "  $r"
done
log "  PASS=${PASS} FAIL=${FAIL} SKIP=${SKIP}"
log "=== End ==="

# Trim old logs — keep last 20 runs
ls -t "$LOG_DIR"/*.log 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null || true

[[ "$FAIL" -eq 0 ]]
