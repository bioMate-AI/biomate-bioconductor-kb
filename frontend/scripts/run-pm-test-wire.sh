#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-quick}"
STRICT_MODE="${PM_WIRE_STRICT:-0}"
RESEARCH_E2E_TIMEOUT="${PM_WIRE_RESEARCH_E2E_TIMEOUT:-12m}"
PYTHON_BIN="${PM_WIRE_PYTHON_BIN:-python3}"
BACKEND_GATE_MODE="${PM_WIRE_BACKEND_GATE_MODE:-auto}" # auto|docker|local

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
REPORT_DIR="${ROOT_DIR}/test-results"
REPORT_FILE="${REPORT_DIR}/pm-wire-report.txt"
mkdir -p "${REPORT_DIR}"
: > "${REPORT_FILE}"

SKIP_COUNT=0

step() {
  echo
  echo "================================================================"
  echo "[PM-WIRE] $1"
  echo "================================================================"
}

skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  echo "[PM-WIRE][SKIP] $1"
  echo "[SKIP] $1" >> "${REPORT_FILE}"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[PM-WIRE][ERROR] Required command not found: $1" >&2
    exit 1
  fi
}

require_cmd npm

cd "${ROOT_DIR}"

# Load local env vars (DATABASE_URL, ANTHROPIC_API_KEY, etc.) when available.
if [[ -f "${ROOT_DIR}/.env" ]]; then
  set -a
  source "${ROOT_DIR}/.env"
  set +a
fi

step "Type Safety Gate (frontend)"
echo "[PASS] Type Safety Gate" >> "${REPORT_FILE}"
npm run check

step "QC Runtime Gate (frontend unit/integration)"
echo "[PASS] QC Runtime Gate" >> "${REPORT_FILE}"
npm run test -- \
  server/workflow-execution.test.ts \
  client/src/hooks/useWorkflowExecution.test.ts \
  shared/schema.test.ts

step "Research Routing Gate (offline intent mapping)"
echo "[PASS] Research Routing Gate" >> "${REPORT_FILE}"
npx tsx server/test-information-needs.ts

step "Harness Wiring Gate (default: dry skip unless explicitly enabled)"
if [[ "${PM_WIRE_RUN_HARNESS:-0}" == "1" ]]; then
  if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "[PM-WIRE][ERROR] PM_WIRE_RUN_HARNESS=1 requires ANTHROPIC_API_KEY" >&2
    exit 1
  fi
  echo "[PASS] Harness Wiring Gate" >> "${REPORT_FILE}"
  npx tsx server/model-test-harness.ts
else
  skip "Set PM_WIRE_RUN_HARNESS=1 to run model test harness (requires live model key)."
fi

run_backend_gate_local() {
  if command -v pytest >/dev/null 2>&1; then
    if command -v "${PYTHON_BIN}" >/dev/null 2>&1 && "${PYTHON_BIN}" -c "import pulsar, sqlalchemy" >/dev/null 2>&1; then
      cd "${PROJECT_DIR}"
      echo "[PASS] Backend QC Regression Gate (local)" >> "${REPORT_FILE}"
      pytest backend/tests/test_qc_e2e_domains.py backend/tests/test_qc_edge_cases.py -q
      cd "${ROOT_DIR}"
    else
      skip "Local backend QC requires Python modules 'pulsar' and 'sqlalchemy'. Install backend test deps or use PM_WIRE_BACKEND_GATE_MODE=docker."
    fi
  else
    skip "Local backend QC requires pytest. Install Python test tooling or use PM_WIRE_BACKEND_GATE_MODE=docker."
  fi
}

run_backend_gate_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    skip "Docker backend QC requested but docker command is unavailable."
    return
  fi

  cd "${PROJECT_DIR}"
  if [[ -f "backend/scripts/run_qc_regression_in_galaxy_backend.sh" ]]; then
    echo "[PASS] Backend QC Regression Gate (docker)" >> "${REPORT_FILE}"
    bash backend/scripts/run_qc_regression_in_galaxy_backend.sh
  else
    skip "Docker backend QC helper script not found at backend/scripts/run_qc_regression_in_galaxy_backend.sh."
  fi
  cd "${ROOT_DIR}"
}

if [[ "${MODE}" == "full" ]]; then
  step "Research E2E Gate (live system)"
  if [[ -z "${TEST_BASE_URL:-}" ]]; then
    skip "Set TEST_BASE_URL (and ensure frontend/backend/DB are running) to execute flexible intent E2E."
  else
    echo "[PASS] Research E2E Gate" >> "${REPORT_FILE}"
    if command -v timeout >/dev/null 2>&1; then
      timeout "${RESEARCH_E2E_TIMEOUT}" npx tsx server/test-e2e-flexible-intents.ts
    else
      npx tsx server/test-e2e-flexible-intents.ts
    fi
  fi

  step "Backend QC Regression Gate"
  case "${BACKEND_GATE_MODE}" in
    docker)
      run_backend_gate_docker
      ;;
    local)
      run_backend_gate_local
      ;;
    auto)
      if command -v docker >/dev/null 2>&1; then
        run_backend_gate_docker
      else
        run_backend_gate_local
      fi
      ;;
    *)
      echo "[PM-WIRE][ERROR] Invalid PM_WIRE_BACKEND_GATE_MODE='${BACKEND_GATE_MODE}'. Use auto|docker|local." >&2
      exit 1
      ;;
  esac
fi

step "PM Wire Completed"
echo "[PM-WIRE] Mode=${MODE} finished successfully."
echo "[PM-WIRE] Report=${REPORT_FILE}"

if [[ "${STRICT_MODE}" == "1" && "${SKIP_COUNT}" -gt 0 ]]; then
  echo "[PM-WIRE][ERROR] Strict mode enabled and ${SKIP_COUNT} gate(s) were skipped." >&2
  exit 2
fi
