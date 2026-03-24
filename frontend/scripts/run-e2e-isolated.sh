#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="${ROOT_DIR}/e2e/test-results-isolated/${STAMP}"

mkdir -p "${OUT_DIR}"

echo "[e2e-isolated] Using output directory: ${OUT_DIR}"
echo "[e2e-isolated] Running: npx playwright test $*"

PW_OUTPUT_DIR="${OUT_DIR}" npx playwright test "$@"
