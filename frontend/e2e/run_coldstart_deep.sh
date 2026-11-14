#!/usr/bin/env bash
# Single-writer runner for coldstart-analysis-design-deep.e2e.ts.
#
# Problem this fixes: multiple agents / terminals launching
#   npx playwright test e2e/coldstart-analysis-design-deep.e2e.ts
# in parallel → mutual pkill, EXIT 143, wiped evidence, disk thrash.
#
# Rule: ONLY this script may start that suite. It holds an exclusive flock
# for the whole sequential lane plan (or one filtered slice).
#
# Usage:
#   cd frontend
#   BIOMATE_URL=https://dev-public.biomate.ai ./e2e/run_coldstart_deep.sh
#   BIOMATE_DEEP_FILTER='^design-rank-' ./e2e/run_coldstart_deep.sh   # one slice
#   BIOMATE_DEEP_LANES=all ./e2e/run_coldstart_deep.sh                # default
#   BIOMATE_DEEP_WORKERS=2 ./e2e/run_coldstart_deep.sh
#
# Env:
#   BIOMATE_URL                 default https://dev-public.biomate.ai
#   BIOMATE_DEEP_FILTER         if set, run ONLY that regex (skip lane plan)
#   BIOMATE_DEEP_LANES          all | analysis | design  (ignored if FILTER set)
#   BIOMATE_DEEP_WORKERS        default 1 (one-writer; never parallel thrash)
#   BIOMATE_DEEP_LOCK_WAIT_SEC  flock wait (default 30; 0 = fail immediate)
#   BIOMATE_DEEP_MIN_FREE_GI    abort if free disk below this (default 3)
#   E2E_FIXTURE_PASSWORD        or ~/.config/biomate/e2e_fixture_password

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCK_DIR="${BIOMATE_DEEP_LOCK_DIR:-/tmp/biomate_coldstart_deep.lock}"
LOCK_WAIT="${BIOMATE_DEEP_LOCK_WAIT_SEC:-30}"
WORKERS="${BIOMATE_DEEP_WORKERS:-1}"
# Hard floor 3 Gi (user/ops gate). Override only with BIOMATE_DEEP_MIN_FREE_GI.
MIN_FREE_GI="${BIOMATE_DEEP_MIN_FREE_GI:-3}"
export BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"

unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy SOCKS_PROXY SOCKS5_PROXY || true
export NO_PROXY='*'

if [[ -z "${E2E_FIXTURE_PASSWORD:-}" && -f "${HOME}/.config/biomate/e2e_fixture_password" ]]; then
  E2E_FIXTURE_PASSWORD="$(tr -d '\n' < "${HOME}/.config/biomate/e2e_fixture_password")"
  export E2E_FIXTURE_PASSWORD
fi
if [[ -z "${E2E_FIXTURE_PASSWORD:-}" ]]; then
  echo "FATAL: E2E_FIXTURE_PASSWORD unset and ~/.config/biomate/e2e_fixture_password missing" >&2
  exit 2
fi

free_gi() {
  # macOS APFS: Available from df -g
  df -g /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4}' || df -g / | awk 'NR==2{print $4}'
}

# True only for live node/npm/npx Playwright workers on this suite.
# Broad `pgrep …e2e.ts` false-positives: bash -lc wrappers, git diff path lists.
peer_deep_playwright() {
  pgrep -fl 'playwright test .*coldstart-analysis-design-deep\.e2e\.ts' 2>/dev/null \
    | grep -E '^(node|npm|npx|[0-9]+ +(node|npm|npx) )' || true
}

FREE="$(free_gi || echo 0)"
FREE_INT="${FREE%%.*}"
if [[ "$FREE_INT" -lt "$MIN_FREE_GI" ]]; then
  echo "FATAL: free disk ${FREE} Gi < BIOMATE_DEEP_MIN_FREE_GI=${MIN_FREE_GI}. Free space before deep E2E." >&2
  df -h /System/Volumes/Data | tail -1 >&2 || true
  exit 3
fi
# Drop regenerable suite artifacts in THIS worktree before starting (keeps JSON evidence).
rm -rf "$ROOT/e2e/test-results" "$ROOT/playwright-report" 2>/dev/null || true
mkdir -p "$ROOT/e2e/test-results"

PEERS="$(peer_deep_playwright)"
if [[ -n "$PEERS" ]]; then
  echo "FATAL: another coldstart-analysis-design-deep Playwright is already running:" >&2
  echo "$PEERS" >&2
  echo "Stop it (or wait), then re-run ONLY via $0 — never raw npx / ALLOW_PARALLEL agents." >&2
  exit 4
fi

# Portable exclusive lock (macOS has no util-linux `flock`).
# Atomic mkdir of HOLD_DIR; owner lives INSIDE hold so a peer cleanup cannot
# unlink our owner while Playwright workers are still running.
HOLD_DIR="$LOCK_DIR/hold"
OWNER_FILE="$HOLD_DIR/owner"
# Compat path the suite also checks (LOCK_DIR/owner) — keep as symlink/copy.
OWNER_LINK="$LOCK_DIR/owner"
mkdir -p "$LOCK_DIR"

acquire_lock() {
  local deadline=$(( $(date +%s) + LOCK_WAIT ))
  while true; do
    if mkdir "$HOLD_DIR" 2>/dev/null; then
      return 0
    fi
    local opid=""
    if [[ -f "$OWNER_FILE" ]]; then
      opid="$(awk -F= '/^pid=/{print $2; exit}' "$OWNER_FILE" 2>/dev/null || true)"
    elif [[ -f "$OWNER_LINK" ]]; then
      opid="$(awk -F= '/^pid=/{print $2; exit}' "$OWNER_LINK" 2>/dev/null || true)"
    fi
    if [[ -n "$opid" ]] && ! kill -0 "$opid" 2>/dev/null; then
      echo "WARN: breaking stale lock (dead pid=$opid)" >&2
      rm -rf "$HOLD_DIR"
      rm -f "$OWNER_LINK"
      continue
    fi
    if [[ ! -d "$HOLD_DIR" ]]; then
      continue
    fi
    if (( $(date +%s) >= deadline )); then
      return 1
    fi
    sleep 1
  done
}

if ! acquire_lock; then
  echo "FATAL: could not acquire $LOCK_DIR within ${LOCK_WAIT}s" >&2
  [[ -f "$OWNER_FILE" ]] && cat "$OWNER_FILE" >&2
  [[ -f "$OWNER_LINK" ]] && cat "$OWNER_LINK" >&2
  exit 5
fi

{
  echo "pid=$$"
  echo "host=$(hostname)"
  echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "filter=${BIOMATE_DEEP_FILTER:-}"
  echo "lanes=${BIOMATE_DEEP_LANES:-all}"
  echo "url=$BIOMATE_URL"
} | tee "$OWNER_FILE" >"$OWNER_LINK"
export BIOMATE_DEEP_VIA_RUNNER=1
export BIOMATE_DEEP_LOCK_DIR="$LOCK_DIR"

cleanup() {
  # Only the holder removes the hold dir (owner lives inside it).
  if [[ -f "$OWNER_FILE" ]] && grep -q "^pid=$$\$" "$OWNER_FILE" 2>/dev/null; then
    rm -rf "$HOLD_DIR"
    rm -f "$OWNER_LINK"
  fi
}
trap cleanup EXIT

write_owner() {
  {
    echo "pid=$$"
    echo "host=$(hostname)"
    echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "filter=${1:-${BIOMATE_DEEP_FILTER:-}}"
    echo "lanes=${BIOMATE_DEEP_LANES:-all}"
    echo "url=$BIOMATE_URL"
  } | tee "$OWNER_FILE" >"$OWNER_LINK"
}

run_slice() {
  local filter="$1"
  local tag
  tag="$(echo "$filter" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-80)"
  local log="/tmp/biomate_coldstart_deep_${tag}_$(date -u +%Y%m%dT%H%M%SZ).log"
  echo ""
  echo "======== SLICE filter=$filter workers=$WORKERS ========"
  echo "LOG=$log"
  write_owner "$filter"
  # Re-check no peer slipped in (agents that ignore this script / ALLOW_PARALLEL).
  local peers
  peers="$(peer_deep_playwright)"
  if [[ -n "$peers" ]]; then
    echo "FATAL: peer Playwright appeared before slice start:" >&2
    echo "$peers" >&2
    return 4
  fi
  BIOMATE_DEEP_FILTER="$filter" BIOMATE_DEEP_VIA_RUNNER=1 \
    npx playwright test \
    e2e/coldstart-analysis-design-deep.e2e.ts \
    --project=chromium --retries=0 --workers="$WORKERS" \
    2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  echo "SLICE_EXIT=$rc filter=$filter"
  return "$rc"
}

# Default sequential lane plan — one flock covers all; never parallel agents.
LANES_ANALYSIS=(
  '^analysis-(ad-hoc-compute|validated-workflows)-'
  '^(analysis-try-sample-data-|analysis-domain-(dd|txn|gen)-)'
  '^analysis-domain-(fgen|str|prot|clin)-'
)
LANES_DESIGN=(
  '^design-(generate|fold-complex)-'
  '^design-(predict-filter|optimise-properties-one-pass)-'
  '^design-rank-candidates-'
)

FAIL=0
if [[ -n "${BIOMATE_DEEP_FILTER:-}" ]]; then
  set +e
  run_slice "$BIOMATE_DEEP_FILTER"
  FAIL=$?
  set -e
else
  case "${BIOMATE_DEEP_LANES:-all}" in
    analysis) PLAN=("${LANES_ANALYSIS[@]}") ;;
    design) PLAN=("${LANES_DESIGN[@]}") ;;
    all) PLAN=("${LANES_ANALYSIS[@]}" "${LANES_DESIGN[@]}") ;;
    *)
      echo "FATAL: BIOMATE_DEEP_LANES must be all|analysis|design" >&2
      exit 2
      ;;
  esac
  for f in "${PLAN[@]}"; do
    write_owner "$f"
    # Capture rc before any `if !` would clobber $? to 0.
    set +e
    run_slice "$f"
    local_rc=$?
    set -e
    if [[ "$local_rc" -ne 0 ]]; then
      FAIL="$local_rc"
      echo "WARN: slice failed (rc=$FAIL); continuing remaining lanes under same lock"
    fi
  done
fi

echo "DONE fail=$FAIL owner was pid=$$"
exit "$FAIL"
