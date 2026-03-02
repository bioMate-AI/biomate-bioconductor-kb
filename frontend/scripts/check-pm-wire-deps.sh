#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"

ok() {
  echo "[OK]   $1"
}

warn() {
  echo "[MISS] $1"
}

echo "PM Wire dependency preflight"
echo "============================"

command -v npm >/dev/null 2>&1 && ok "npm available" || warn "npm missing"
command -v npx >/dev/null 2>&1 && ok "npx available" || warn "npx missing"
command -v python3 >/dev/null 2>&1 && ok "python3 available" || warn "python3 missing"
command -v pytest >/dev/null 2>&1 && ok "pytest available" || warn "pytest missing"

if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import pulsar" >/dev/null 2>&1; then
    ok "python module pulsar available"
  else
    warn "python module pulsar missing (needed for backend QC regression gate)"
  fi
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  ok "ANTHROPIC_API_KEY set (harness gate can run)"
else
  warn "ANTHROPIC_API_KEY not set (harness gate will skip)"
fi

if [[ -n "${TEST_BASE_URL:-}" ]]; then
  ok "TEST_BASE_URL set (${TEST_BASE_URL})"
else
  warn "TEST_BASE_URL not set (research E2E gate will skip)"
fi

if [[ -n "${TEST_BASE_URL:-}" ]]; then
  if command -v curl >/dev/null 2>&1 && curl -fsS "${TEST_BASE_URL}/api/health" >/dev/null 2>&1; then
    ok "TEST_BASE_URL health endpoint reachable"
  else
    warn "TEST_BASE_URL not reachable at /api/health"
  fi
fi

echo
echo "Suggested next command:"
echo "  cd \"${ROOT_DIR}\" && npm run pm:wire:release"
echo
echo "Project root: ${PROJECT_DIR}"
