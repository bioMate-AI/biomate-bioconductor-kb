#!/bin/bash
# Full gunicorn smoke-boot for the Galaxy backend.
#
# Boots a real ASGI worker against a throwaway sqlite, polls the API
# until healthy, and reports any startup-time errors. Catches the class
# of bugs that the lighter scripts/smoke_pydantic_models.py cannot:
#
#   - FastAPI Depends resolution failures (the auth chain, etc.)
#   - SQLAlchemy mapper-build errors at startup
#   - Plugin / tool-shed import-side-effects
#   - Anything that lives behind `if __name__` or `@app.on_event("startup")`
#
# Exit codes:
#   0  app booted and reached healthy state within timeout
#   1  worker failed to boot (e.g. Pydantic forward-ref) or never healthy
#   2  precondition (venv, gunicorn binary, etc.) missing
#
# Usage:
#   scripts/smoke_boot.sh                # default port 9091, 60s timeout
#   PORT=9092 TIMEOUT=90 scripts/smoke_boot.sh
#
# CI: see .github/workflows/backend-smoke-boot.yml

set -uo pipefail

PORT="${PORT:-9091}"
TIMEOUT="${TIMEOUT:-60}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_BIN="${REPO_ROOT}/backend/.venv/bin"
BACKEND_DIR="${REPO_ROOT}/backend"
TMP_DIR=$(mktemp -d)
LOG="${TMP_DIR}/gunicorn.log"
SQLITE="${TMP_DIR}/smoke.sqlite"
PIDFILE="${TMP_DIR}/gunicorn.pid"

cleanup() {
  if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "${PID:-}" ] && kill -0 "$PID" 2>/dev/null; then
      kill -TERM "$PID" 2>/dev/null || true
      sleep 1
      kill -KILL "$PID" 2>/dev/null || true
    fi
  fi
  # Backstop: any gunicorn process on our port
  pkill -f "gunicorn.*$PORT" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ ! -x "${VENV_BIN}/gunicorn" ]; then
  echo "[smoke-boot] FAIL: ${VENV_BIN}/gunicorn missing" >&2
  exit 2
fi

# Free up the port if a previous run left something there
pkill -f "gunicorn.*${PORT}" 2>/dev/null || true
sleep 1

echo "[smoke-boot] booting against $SQLITE on :$PORT (timeout ${TIMEOUT}s)"

# Throwaway env so we don't touch the real Redis / Lago / Anthropic API
# during boot. Most app-startup paths only need the database to be reachable;
# anything that depends on a live external service should be optional at
# boot time (it's a real bug if it isn't).
cd "$BACKEND_DIR"
export GALAXY_CONFIG_DATABASE_CONNECTION="sqlite:///${SQLITE}"
export GALAXY_CONFIG_INSTALL_DATABASE_CONNECTION="sqlite:///${SQLITE}"
export GALAXY_CONFIG_FILE="lib/galaxy/config/sample/galaxy.yml.sample"
export GALAXY_CONFIG_ENABLE_AI_ASSISTANT="false"
export BIOMATE_SMOKE_BOOT="1"
# Boot with billing UNCONFIGURED on purpose. billing_router no longer raises at
# import when its secrets are missing — it degrades (boots, then fails billing
# endpoints closed at request time). Running the smoke without BILLING_DEV_MODE
# guards that boot-resilience: a reintroduced import-time billing crash fails
# here. (Override BILLING_DEV_MODE=true locally for the dev-insecure defaults.)
export BILLING_DEV_MODE="${BILLING_DEV_MODE:-}"
# Don't reach out to real services on import
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-sk-fake-smoke}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-sk-fake-smoke}"
export GEMINI_API_KEY="${GEMINI_API_KEY:-fake-smoke}"

"${VENV_BIN}/gunicorn" \
  "galaxy.webapps.galaxy.fast_factory:factory()" \
  --bind "127.0.0.1:${PORT}" \
  --workers 1 \
  --timeout 90 \
  --graceful-timeout 5 \
  --pythonpath lib \
  -k uvicorn.workers.UvicornWorker \
  --pid "$PIDFILE" \
  > "$LOG" 2>&1 &
LAUNCHER_PID=$!

# Poll until healthy or fail.
DEADLINE=$(($(date +%s) + TIMEOUT))
HEALTHY=0
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  # Worker failure short-circuit: gunicorn writes "Worker failed to boot"
  # to stderr when a Pydantic forward-ref / import error blows up startup.
  if grep -q "Worker failed to boot\|Reason: Worker failed" "$LOG" 2>/dev/null; then
    echo "[smoke-boot] FAIL: worker failed to boot" >&2
    echo "--- last 60 lines of gunicorn log ---" >&2
    tail -60 "$LOG" >&2
    exit 1
  fi

  if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/api/version" 2>/dev/null; then
    HEALTHY=1
    break
  fi
  if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:${PORT}/api/parameter_inference/health" 2>/dev/null; then
    HEALTHY=1
    break
  fi
  sleep 1
done

if [ "$HEALTHY" -ne 1 ]; then
  echo "[smoke-boot] FAIL: app did not reach healthy state within ${TIMEOUT}s" >&2
  echo "--- last 80 lines of gunicorn log ---" >&2
  tail -80 "$LOG" >&2
  exit 1
fi

# Specifically probe the routes we just added — confirms FastAPI route
# registration didn't silently skip a router.
PROBES=(
  "/api/ind-report/projects/p-bm0042/pipeline_data"
  "/api/ind-report/projects/p-bm0042/params/admet"
  "/api/auth/mfa/status"
)
PROBE_FAILS=0
for path in "${PROBES[@]}"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${PORT}${path}" 2>/dev/null)
  # Accept any non-5xx — a 401 from MFA means the route is registered.
  if [ -z "$code" ] || [ "$code" -ge 500 ]; then
    echo "[smoke-boot] probe FAIL: $path returned HTTP $code" >&2
    PROBE_FAILS=$((PROBE_FAILS + 1))
  else
    echo "[smoke-boot] probe ok: $path -> $code"
  fi
done

if [ "$PROBE_FAILS" -gt 0 ]; then
  echo "[smoke-boot] FAIL: $PROBE_FAILS probe(s) returned 5xx or no response" >&2
  echo "--- last 60 lines of gunicorn log ---" >&2
  tail -60 "$LOG" >&2
  exit 1
fi

echo "[smoke-boot] PASS: app booted, ${#PROBES[@]}/${#PROBES[@]} route probes ok"
exit 0
