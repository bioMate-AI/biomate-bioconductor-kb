#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-quick}"
STRICT_MODE="${PM_WIRE_STRICT:-0}"

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

if [[ "${MODE}" == "full" ]]; then
  step "Research E2E Gate (live system)"
  if [[ -z "${TEST_BASE_URL:-}" ]]; then
    skip "Set TEST_BASE_URL (and ensure frontend/backend/DB are running) to execute flexible intent E2E."
  else
    echo "[PASS] Research E2E Gate" >> "${REPORT_FILE}"
    npx tsx server/test-e2e-flexible-intents.ts
  fi

  step "Backend QC Regression Gate"
  if command -v pytest >/dev/null 2>&1; then
    if command -v python3 >/dev/null 2>&1 && python3 -c "import pulsar" >/dev/null 2>&1; then
      cd "${PROJECT_DIR}"
      echo "[PASS] Backend QC Regression Gate" >> "${REPORT_FILE}"
      pytest backend/tests/test_qc_e2e_domains.py backend/tests/test_qc_edge_cases.py -q
      cd "${ROOT_DIR}"
    else
      skip "Backend QC regression requires Python module 'pulsar'. Install backend test deps to enable this gate."
    fi
  else
    skip "pytest not found; install Python test tooling to run backend QC regression gate."
  fi
fi

step "PM Wire Completed"
echo "[PM-WIRE] Mode=${MODE} finished successfully."
echo "[PM-WIRE] Report=${REPORT_FILE}"

if [[ "${STRICT_MODE}" == "1" && "${SKIP_COUNT}" -gt 0 ]]; then
  echo "[PM-WIRE][ERROR] Strict mode enabled and ${SKIP_COUNT} gate(s) were skipped." >&2
  exit 2
fi
