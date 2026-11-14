#!/usr/bin/env bash
# run_ux_audit.sh — one-command live UX walkthrough audit against dev + the Claude design reference.
#
# WHY THIS SCRIPT: the live/visual UX audit (CLAUDE.md "UX E2E Completeness Standard") needs a browser
# env that (a) can launch Playwright's chromium and (b) can reach http://localhost:7779 (the reference
# design server). A sandboxed agent env typically blocks loopback + has a browser-version mismatch, so
# the live audit must run on a real machine (yours). This wraps all the setup into one command.
#
# USAGE:
#   E2E_FIXTURE_PASSWORD='<the fixture pw>' bash scripts/run_ux_audit.sh [structural|reference|all]
#     structural  — dev-targeting journeys: researcher-journey, sidebar-all-buttons, panel-and-chat-stream
#     reference   — reference-vs-dev visual demos: demo-08/09/10 (need the :7779 reference server)
#     all         — both (default)
#
# PREREQS: python3, node/npm, and the fixture password (or it in frontend/.env.local). Targets dev
# (https://dev-public.biomate.ai) by default; override with BIOMATE_URL. Read-only to the repo; it
# only drives the browser + starts a local static server for the reference design.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REF_DIR="$REPO_ROOT/reference/claude_design"
FRONTEND="$REPO_ROOT/frontend"
SCOPE="${1:-all}"

export BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
export E2E_TEST_TOKEN="${E2E_TEST_TOKEN:-biomate-e2e-bypass-token-dev-only}"

say() { printf '\n\033[1;36m[ux-audit]\033[0m %s\n' "$*"; }
fail() { printf '\n\033[1;31m[ux-audit] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null || fail "python3 not found"
command -v npx >/dev/null || fail "npx not found"
[ -d "$FRONTEND" ] || fail "frontend/ not found at $FRONTEND"
[ -d "$REF_DIR" ] || fail "reference design not found at $REF_DIR"

# Fixture password: required unless present in frontend/.env.local (playwright.config loads dotenv).
if [ -z "${E2E_FIXTURE_PASSWORD:-}" ] && ! grep -q 'E2E_FIXTURE_PASSWORD' "$FRONTEND/.env.local" 2>/dev/null; then
  fail "E2E_FIXTURE_PASSWORD is unset and not in frontend/.env.local. Export it: E2E_FIXTURE_PASSWORD='...' bash scripts/run_ux_audit.sh"
fi

cd "$FRONTEND"

say "Ensuring Playwright chromium is installed (fixes the agent-env build mismatch)..."
npx playwright install chromium || fail "playwright install chromium failed"

REF_PID=""
cleanup() { [ -n "$REF_PID" ] && kill "$REF_PID" 2>/dev/null || true; }
trap cleanup EXIT

start_ref_server() {
  say "Starting reference design server on :7779 (dir: $REF_DIR)..."
  python3 -m http.server 7779 --directory "$REF_DIR" >/tmp/ux_ref_7779.log 2>&1 &
  REF_PID=$!
  for i in $(seq 1 15); do
    if curl -sf -o /dev/null --max-time 3 "http://localhost:7779/cro/Workflow%20Panel%20Redesign.html" 2>/dev/null; then
      say "Reference server reachable."; return 0
    fi
    sleep 1
  done
  fail "Reference server not reachable at localhost:7779 — your env may block loopback (then the 'reference' scope can't run; use 'structural')."
}

STRUCTURAL="e2e/researcher-journey.e2e.ts e2e/sidebar-all-buttons.e2e.ts e2e/panel-and-chat-stream.e2e.ts"
REFERENCE="e2e/demo-08-workflow-panel-tour.demo.ts e2e/demo-09-reference-workflow-panel.demo.ts e2e/demo-10-workflow-panel-reference.demo.ts"

rc=0
case "$SCOPE" in
  structural|all)
    say "Running STRUCTURAL journeys against $BIOMATE_URL (chromium project)..."
    npx playwright test $STRUCTURAL --project chromium --reporter=line --retries=0 || rc=$?
    ;;
esac
case "$SCOPE" in
  reference|all)
    start_ref_server
    say "Running REFERENCE visual demos (dev vs localhost:7779) (demo project)..."
    npx playwright test $REFERENCE --project demo --reporter=line --retries=0 || rc=$?
    ;;
esac
[ "$SCOPE" = structural ] || [ "$SCOPE" = reference ] || [ "$SCOPE" = all ] || fail "unknown scope '$SCOPE' (use structural|reference|all)"

say "Done (playwright exit: $rc). Screenshots + HTML report:"
echo "   report:      $FRONTEND/e2e/reports/index.html   (open with: cd frontend && npm run e2e:report)"
echo "   screenshots: $FRONTEND/e2e/reports/data/ and test-results/   (screenshot:'on' captures every step)"
echo "   Compare the dev captures against the reference design at http://localhost:7779 and note deviations."
exit $rc
