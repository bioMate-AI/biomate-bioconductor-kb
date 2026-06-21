#!/usr/bin/env bash
# Post-sync E2E test runner — called by sync_to_dev.sh after each successful sync.
# Runs the targeted test suites against dev-public.biomate.ai and logs results.
#
# Usage: bash scripts/run_postsync_tests.sh [commit_id]
#
# Output: docs/postsync_test_results/<date>_<commit>.log
#         Exit 0 = all pass, Exit 1 = failures

set -uo pipefail
# NOTE: deliberately NOT using `set -e` — a single suite failure (or a
# SIGPIPE from a caller's `| tail`) must not abort the runner before
# later suites get a chance, and must not corrupt the final exit code.
# Caller's exit-code contract: 0 == every executed suite passed,
# 1 == at least one suite failed, 2 == runner aborted abnormally.

# Ignore SIGPIPE so that callers piping our stdout (e.g. `| tail`) cannot
# kill the script mid-run when their reader closes early.
trap '' PIPE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT="${1:-$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
DATE="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$REPO_ROOT/docs/postsync_test_results"
LOG_FILE="$LOG_DIR/${DATE}_${COMMIT}.log"
BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
FRONTEND_DIR="$REPO_ROOT/frontend"

mkdir -p "$LOG_DIR"

# Write to the file directly and then echo — never pipe through `tee`,
# which propagates SIGPIPE back into the script when the caller's reader
# closes (e.g. `bash run_postsync_tests.sh | tail -5`).
log() {
  local line="[$(date +%H:%M:%S)] $*"
  printf '%s\n' "$line" >> "$LOG_FILE" || true
  printf '%s\n' "$line" 2>/dev/null || true
}

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
    SKIP=$((SKIP + 1))
    continue
  fi

  log "[RUN]  $label ($file) ..."
  suite_log="$LOG_DIR/${DATE}_${COMMIT}_${label}.log"

  BIOMATE_URL="$BIOMATE_URL" \
    npx playwright test "$suite_path" \
      --timeout "$timeout_ms" \
      --reporter=list \
      >> "$suite_log" 2>&1
  rc=$?

  if [[ $rc -eq 0 ]]; then
    passed=$(grep -oE "[0-9]+ passed" "$suite_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+" || true)
    log "[PASS] $label — ${passed:-?} test(s) passed"
    RESULTS+=("PASS  $label")
    PASS=$((PASS + 1))
  else
    failed=$(grep -oE "[0-9]+ failed" "$suite_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+" || true)
    skipped=$(grep -oE "[0-9]+ skipped" "$suite_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+" || true)
    log "[FAIL] $label — ${failed:-?} failed, ${skipped:-0} skipped — see $suite_log"
    {
      echo "--- tail: $suite_log ---"
      tail -30 "$suite_log" 2>/dev/null || true
      echo "--- end tail ---"
    } >> "$LOG_FILE" 2>/dev/null || true
    RESULTS+=("FAIL  $label")
    FAIL=$((FAIL + 1))
  fi
done

# ---------------------------------------------------------------------------
# MCP connector tests — run against dev after Playwright suites complete
# Requires: BIOMATE_CONNECTOR_API_KEY env var set on dev EC2
# Skipped gracefully when key is absent (CI will still run Playwright suites)
# ---------------------------------------------------------------------------
# BIOMATE_CONNECTOR_DIR — path to the biomate-connector repo on this machine.
# Set in the deploy environment; script skips MCP tests gracefully if absent.
_connector_dir="${BIOMATE_CONNECTOR_DIR:-}"
# Fallback: look for sibling directory (works on dev EC2 where repos are co-located)
if [[ -z "$_connector_dir" ]]; then
  _candidate="$(cd "$REPO_ROOT/../biomate-connector" 2>/dev/null && pwd || true)"
  [[ -d "$_candidate" ]] && _connector_dir="$_candidate"
fi
MCP_TEST_FILE="${_connector_dir:+${_connector_dir}/tests/test_mcp_e2e.py}"
CONNECTOR_KEY="${BIOMATE_CONNECTOR_API_KEY:-}"

if [[ -f "$MCP_TEST_FILE" && -n "$CONNECTOR_KEY" ]]; then
  log "[RUN]  mcp-e2e (test_mcp_e2e.py) against ${BIOMATE_URL} ..."
  mcp_log="$LOG_DIR/${DATE}_${COMMIT}_mcp-e2e.log"
  BIOMATE_API_URL="$BIOMATE_URL" \
  BIOMATE_API_KEY="$CONNECTOR_KEY" \
    python3 -m pytest "$MCP_TEST_FILE" -v \
      >> "$mcp_log" 2>&1
  mcp_rc=$?
  if [[ $mcp_rc -eq 0 ]]; then
    passed=$(grep -oE "[0-9]+ passed" "$mcp_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+" || true)
    log "[PASS] mcp-e2e — ${passed:-?} test(s) passed"
    RESULTS+=("PASS  mcp-e2e")
    PASS=$((PASS + 1))
  else
    failed=$(grep -oE "[0-9]+ failed" "$mcp_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+" || true)
    skipped=$(grep -oE "[0-9]+ skipped" "$mcp_log" 2>/dev/null | tail -1 | grep -oE "[0-9]+" || true)
    log "[FAIL] mcp-e2e — ${failed:-?} failed, ${skipped:-0} skipped — see $mcp_log"
    {
      echo "--- tail: $mcp_log ---"
      tail -30 "$mcp_log" 2>/dev/null || true
      echo "--- end tail ---"
    } >> "$LOG_FILE" 2>/dev/null || true
    RESULTS+=("FAIL  mcp-e2e")
    FAIL=$((FAIL + 1))
  fi
elif [[ ! -f "$MCP_TEST_FILE" ]]; then
  log "[SKIP] mcp-e2e — test file not found at $MCP_TEST_FILE"
  RESULTS+=("SKIP  mcp-e2e")
  SKIP=$((SKIP + 1))
else
  log "[SKIP] mcp-e2e — BIOMATE_CONNECTOR_API_KEY not set"
  RESULTS+=("SKIP  mcp-e2e (no key)")
  SKIP=$((SKIP + 1))
fi

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

# Exit code: 0 only when every suite that ran passed. Suites that were
# SKIPped (file not found) do not count as failures.
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
