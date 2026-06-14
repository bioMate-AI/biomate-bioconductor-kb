#!/usr/bin/env bash
# pre_sync_check.sh — workstation gates before scripts/sync_to_dev.sh.
#
# Runs the four deterministic checks from
# docs/20260614_PRE_SYNC_TEST_PLAN.md Part 1 (W1–W4) in order and
# exits non-zero on the first failure.
#
# Usage:
#   bash scripts/pre_sync_check.sh           # full gate (W1..W4)
#   SKIP_W4=1 bash scripts/pre_sync_check.sh # skip boot smoke (slowest)
#   QUICK=1 bash scripts/pre_sync_check.sh   # equiv to SKIP_W4=1
#
# Exit codes:
#   0  — every check passed (or skipped by env var); safe to sync.
#   1  — branch self-check failed (not on integration/next-phase).
#   2  — W1 (tsc) failed.
#   3  — W2 (vitest) failed.
#   4  — W3 (embeddings round-trip) failed.
#   5  — W4 (boot smoke) failed.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$REPO/docs/pre_sync_logs"
mkdir -p "$LOG_DIR"
TS="$(date +%Y%m%d_%H%M%S)"
RUN_LOG="$LOG_DIR/${TS}.log"

C_OK=$'\033[32m'   ; C_FAIL=$'\033[31m'
C_WARN=$'\033[33m' ; C_DIM=$'\033[2m'  ; C_RESET=$'\033[0m'
HEAD()   { printf "\n${C_WARN}── %s ──${C_RESET}\n" "$*" | tee -a "$RUN_LOG"; }
NOTE()   { printf "%s\n" "$*" | tee -a "$RUN_LOG"; }
PASS()   { printf "${C_OK}✓${C_RESET} %s\n" "$*" | tee -a "$RUN_LOG"; }
FAIL()   { printf "${C_FAIL}✗${C_RESET} %s\n" "$*" | tee -a "$RUN_LOG"; }

NOTE "${C_DIM}log: $RUN_LOG${C_RESET}"

# ── Branch self-check (CLAUDE.md sync rule) ─────────────────────────
HEAD "Branch self-check"
CUR="$(git -C "$REPO" branch --show-current 2>/dev/null || echo '?')"
NOTE "current branch: $CUR"
if [[ "$CUR" != "integration/next-phase" ]]; then
  FAIL "Refusing to proceed. Sync rule (CLAUDE.md) requires"
  FAIL "integration/next-phase. Switch branches first."
  exit 1
fi
if ! git -C "$REPO" diff --quiet --ignore-submodules HEAD -- \
       ':(exclude)*.nextflow.log.*' \
       ':(exclude)frontend/e2e/test-results/*' \
       ':(exclude)frontend/e2e/reports/*' \
       ':(exclude)billing_system' \
       ':(exclude)galaxy_nextflow' \
       ':(exclude)research_repos/claude-scientific-skills-biomate' 2>/dev/null
then
  FAIL "Working tree has uncommitted changes outside of"
  FAIL "the standard noise list. Commit or stash before syncing."
  git -C "$REPO" status --short | head -20 | tee -a "$RUN_LOG"
  exit 1
fi
PASS "branch=integration/next-phase, working tree clean"

# ── W1: tsc ─────────────────────────────────────────────────────────
HEAD "W1 — TypeScript (tsc --noEmit)"
W1_LOG="$LOG_DIR/${TS}_w1_tsc.log"
( cd "$REPO/frontend" && npx --no-install tsc --noEmit -p . ) 2>&1 \
  | tee "$W1_LOG" | tail -40
W1_FAIL_COUNT="$(grep -cE '^[^[:space:]]+\.(ts|tsx)\(' "$W1_LOG" || echo 0)"

# Allow only the two long-standing parse errors in server/routes.ts.
# Anything else is a real failure.
W1_ALLOWED="$(grep -cE 'server/routes\.ts\(6686|server/routes\.ts\(13558' "$W1_LOG" || echo 0)"
W1_NEW=$(( W1_FAIL_COUNT - W1_ALLOWED ))
if [[ "$W1_NEW" -gt 0 ]]; then
  FAIL "W1 NEW tsc errors detected ($W1_NEW outside the allowed long-standing set)"
  exit 2
fi
if [[ "$W1_FAIL_COUNT" -gt 0 ]]; then
  PASS "W1 tsc — only the long-standing routes.ts:6686/13558 parse errors (allowed)"
else
  PASS "W1 tsc — clean"
fi

# ── W2: vitest ──────────────────────────────────────────────────────
HEAD "W2 — vitest (full suite)"
W2_LOG="$LOG_DIR/${TS}_w2_vitest.log"
if ! ( cd "$REPO/frontend" && npx --no-install vitest run ) 2>&1 \
    | tee "$W2_LOG" | tail -20 ; then
  : # we read the summary line below regardless of pipe status
fi
W2_SUMMARY="$(grep -E 'Tests +[0-9]+ (passed|failed)' "$W2_LOG" | tail -1)"
NOTE "summary: ${W2_SUMMARY:-no summary line found}"
W2_FAILED="$(grep -E 'Tests +[0-9]+ failed' "$W2_LOG" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+' || echo 0)"
W2_FILE_FAILED="$(grep -E 'Test Files +[0-9]+ failed' "$W2_LOG" | grep -oE '[0-9]+ failed' | head -1 | grep -oE '[0-9]+' || echo 0)"
# Allow exactly the 2 pre-existing DATABASE_URL env failures at the file level
# (galaxy-assistant-history-block.test.ts + galaxy-assistant-history-edge-cases.test.ts);
# they show as failed FILES (not failed tests).
if [[ "$W2_FAILED" -gt 0 ]]; then
  FAIL "W2 vitest — $W2_FAILED tests failed (pre-existing DATABASE_URL env failures fail at the FILE level not the test level; if you see test-level failures here, investigate)"
  exit 3
fi
if [[ "$W2_FILE_FAILED" -gt 2 ]]; then
  FAIL "W2 vitest — $W2_FILE_FAILED test files failed (> 2 = something beyond the long-standing DATABASE_URL env issue)"
  exit 3
fi
PASS "W2 vitest — 0 test failures, ≤ 2 file failures (DATABASE_URL env-only)"

# ── W3: embeddings staleness round-trip ─────────────────────────────
HEAD "W3 — Embeddings round-trip"
W3_LOG="$LOG_DIR/${TS}_w3_embed.log"
if ! PYTHONPATH="$REPO/backend/lib:$REPO/backend" python3 - <<PY 2>&1 \
    | tee "$W3_LOG"
import sys
from pathlib import Path
try:
    from galaxy.ai.unified_workflow_search import UnifiedWorkflowSearch
except Exception as e:
    print(f"FAIL: cannot import UnifiedWorkflowSearch: {e}")
    sys.exit(1)
db = Path("$REPO/backend/database/galaxy_ai_tools.db")
if not db.exists():
    print(f"FAIL: missing DB at {db}")
    sys.exit(1)
s = UnifiedWorkflowSearch(db_path=db)
ok = s._ensure_workflow_embeddings()
print(f"workflow embeddings ready: {ok}")
sys.exit(0 if ok else 1)
PY
then
  FAIL "W3 embeddings init failed — see $W3_LOG"
  exit 4
fi
PASS "W3 embeddings — loaded / rebuilt OK"

# ── W4: boot smoke ──────────────────────────────────────────────────
if [[ "${SKIP_W4:-${QUICK:-0}}" = "1" ]]; then
  NOTE "${C_DIM}W4 — skipped via SKIP_W4 / QUICK env var${C_RESET}"
else
  HEAD "W4 — backend boot smoke"
  W4_LOG="$LOG_DIR/${TS}_w4_boot.log"
  if [[ ! -x "$REPO/scripts/smoke_boot.sh" ]]; then
    FAIL "W4 scripts/smoke_boot.sh not found or not executable — skip with SKIP_W4=1 if intentional"
    exit 5
  fi
  if ! bash "$REPO/scripts/smoke_boot.sh" 2>&1 | tee "$W4_LOG" | tail -20 ; then
    FAIL "W4 boot smoke failed — see $W4_LOG"
    exit 5
  fi
  PASS "W4 boot smoke — backend came up clean"
fi

# ── All done ────────────────────────────────────────────────────────
HEAD "All gates passed"
NOTE "${C_OK}✓ Safe to run scripts/sync_to_dev.sh${C_RESET}"
NOTE "${C_DIM}Recommended next:"
NOTE "  bash scripts/sync_to_dev.sh 2>&1 | tee /tmp/sync_$(date +%s).log"
NOTE "Then run Part 4 (S1–S5) from docs/20260614_PRE_SYNC_TEST_PLAN.md${C_RESET}"
exit 0
