#!/usr/bin/env bash
# Run the live user-journey suite (frontend/e2e/live-journeys.e2e.ts) against a
# deployed BioMate stack and print a pass/fail table. Exits non-zero if any
# journey fails, is skipped, or does not run — only a demonstrated outcome passes.
#
#   scripts/run_live_journeys.sh                       # against dev
#   BIOMATE_URL=https://other.host scripts/run_live_journeys.sh
#   scripts/run_live_journeys.sh --grep "a\. dataset"  # extra args → playwright
#
# Post-sync hook (add as the last line of scripts/sync_to_dev.sh, after the
# health check):
#   "$REPO_ROOT/scripts/run_live_journeys.sh" || echo "LIVE JOURNEYS FAILED — dev is broken for users"
#
# Credentials: E2E_FIXTURE_PASSWORD, else ~/.config/biomate/e2e_fixture_password.
# Never mocks: every journey hits the real backend as the canonical fixture user,
# creates ONE project and deletes it on teardown.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND="$REPO_ROOT/frontend"
export BIOMATE_URL="${BIOMATE_URL:-https://dev-public.biomate.ai}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${LIVE_JOURNEYS_OUT:-$FRONTEND/e2e/reports}"
mkdir -p "$OUT_DIR"
export LIVE_JOURNEYS_JSON="$OUT_DIR/live-journeys-$STAMP.json"
LOG="$OUT_DIR/live-journeys-$STAMP.log"

if [ -z "${E2E_FIXTURE_PASSWORD:-}" ] && [ ! -s "$HOME/.config/biomate/e2e_fixture_password" ]; then
  echo "ERROR: set E2E_FIXTURE_PASSWORD or create ~/.config/biomate/e2e_fixture_password" >&2
  exit 2
fi

cd "$FRONTEND" || exit 2
if [ ! -d node_modules/@playwright/test ]; then
  echo "Installing frontend dependencies…"
  npm ci --no-audit --no-fund >/dev/null || npm install --no-audit --no-fund >/dev/null || { echo "npm install failed" >&2; exit 2; }
fi

# Install the bundled chromium only if Playwright cannot find it.
if ! node -e "const {chromium}=require('@playwright/test');require('fs').accessSync(chromium.executablePath())" 2>/dev/null; then
  echo "Installing Playwright chromium…"
  npx playwright install chromium || { echo "playwright install chromium failed" >&2; exit 2; }
fi

DEV_COMMIT="$(curl -fsS --max-time 15 "$BIOMATE_URL/build-info.json" 2>/dev/null | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{console.log(JSON.parse(d).commit||"unknown")}catch{console.log("unknown")}})')"
export LIVE_JOURNEYS_DEPLOYED_COMMIT="${DEV_COMMIT:-unknown}"
echo "Live journeys → $BIOMATE_URL   deployed commit: ${DEV_COMMIT:-unknown}   (log: $LOG)"
npx playwright test -c playwright.live.config.ts "$@" 2>&1 | tee "$LOG"
PW_RC=${PIPESTATUS[0]}

if [ ! -s "$LIVE_JOURNEYS_JSON" ]; then
  echo "No JSON report produced (playwright exit $PW_RC) — see $LOG" >&2
  exit "${PW_RC:-1}"
fi

node - "$LIVE_JOURNEYS_JSON" <<'EOF'
const r = require(process.argv[2]);
const rows = [];
const walk = (s) => { (s.specs || []).forEach((sp) => sp.tests.forEach((t) => {
  const res = t.results[t.results.length - 1] || {};
  const skipNote = ((t.annotations || []).concat(res.annotations || []).find((a) => a.type === 'skip') || {}).description;
  const status = !t.results.length ? 'NORUN'
    : (t.status === 'skipped' || res.status === 'skipped') ? (skipNote ? 'SKIP' : 'NORUN')
    : (res.status === 'passed' ? 'PASS' : 'FAIL');
  const why = status === 'NORUN' ? 'not run — an earlier journey in the serial chain failed'
    : status === 'SKIP' ? (skipNote || '')
    : status === 'FAIL' ? ((res.errors && res.errors.length ? res.errors : [res.error || {}])
        .map((e) => String(e.message || '').replace(/\u001b\[[0-9;]*m/g, '').split('\n')[0]).join(' || ')) : '';
  rows.push([status, sp.title, `${((res.duration || 0) / 1000).toFixed(0)}s`, why.slice(0, 400)]);
})); (s.suites || []).forEach(walk); };
(r.suites || []).forEach(walk);
console.log('\n==================== LIVE JOURNEYS ====================');
console.log('target: ' + process.env.BIOMATE_URL + '   deployed commit: ' + (process.env.LIVE_JOURNEYS_DEPLOYED_COMMIT || 'unknown'));
for (const [st, title, dur, why] of rows) console.log(`${st.padEnd(6)} ${title.padEnd(84).slice(0, 84)} ${dur.padStart(5)}  ${why}`);
const fails = rows.filter((r) => r[0] === 'FAIL').length;
console.log(`-------------------------------------------------------\n${rows.length} journeys: ${rows.filter((r) => r[0] === 'PASS').length} pass, ${fails} fail, ${rows.filter((r) => r[0] === 'SKIP').length} skip, ${rows.filter((r) => r[0] === 'NORUN').length} not run`);
if (!rows.length) console.log('NO JOURNEYS RAN — treating as failure');
// Standing rule: a journey is green ONLY if the user outcome happened on the
// deployed stack. SKIP / NORUN are not green — they fail the run too.
const notGreen = rows.filter((r) => r[0] !== 'PASS');
if (notGreen.some((r) => r[0] === 'SKIP')) console.log('SKIPPED journeys count as FAIL (outcome not demonstrated): ' + notGreen.filter((r) => r[0] === 'SKIP').map((r) => r[1].split('.')[0]).join(', '));
process.exitCode = notGreen.length || !rows.length ? 1 : 0;
EOF
TABLE_RC=$?
[ "$PW_RC" -ne 0 ] && exit "$PW_RC"
exit "$TABLE_RC"
