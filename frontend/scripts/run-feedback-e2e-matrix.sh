#!/usr/bin/env bash

set -u
set -o pipefail

BASE_URL="${BIOMATE_URL:-http://localhost:5000}"
PROJECT="${PLAYWRIGHT_PROJECT:-chromium}"
MATRIX_MODE="${FEEDBACK_MATRIX_MODE:-full}"
STRICT_NO_SKIP_CRITICAL="${STRICT_NO_SKIP_CRITICAL:-false}"
USE_ISOLATED_OUTPUTS="${E2E_ISOLATED_OUTPUTS:-true}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_JSON="${ROOT_DIR}/package.json"
PLAYWRIGHT_CONFIG="${ROOT_DIR}/playwright.config.ts"
LOCK_FILE="${ROOT_DIR}/.e2e-feedback-matrix.lock"
RUN_META_DIR="${ROOT_DIR}/e2e/matrix-runs"
RUN_TS="$(date +%Y%m%d_%H%M%S)"
RUN_META_FILE="${RUN_META_DIR}/feedback-matrix-run-${RUN_TS}.txt"
RUN_ARTIFACT_DIR="${RUN_META_DIR}/feedback-matrix-run-${RUN_TS}"
MATRIX_LOG_FILE="${RUN_ARTIFACT_DIR}/matrix-console.log"

required_files=(
  "${PACKAGE_JSON}"
  "${PLAYWRIGHT_CONFIG}"
)

hash_file() {
  local file_path="$1"
  sha256sum "${file_path}" | awk '{print $1}'
}

preflight_check() {
  for file_path in "${required_files[@]}"; do
    if [[ ! -f "${file_path}" ]]; then
      echo "FATAL: required file missing: ${file_path}"
      echo "Hint: stop parallel workspace changes (branch checkout/sync/clean) and restore file before running matrix."
      exit 2
    fi
  done
}

write_run_metadata() {
  local exit_code="$1"
  local matrix_end_ts
  local matrix_elapsed_local
  local git_branch
  local git_commit
  matrix_end_ts="$(date +%s)"
  matrix_elapsed_local=$((matrix_end_ts - matrix_start))
  git_branch="$(git -C "${ROOT_DIR}/.." rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  git_commit="$(git -C "${ROOT_DIR}/.." rev-parse --short HEAD 2>/dev/null || echo "unknown")"

  mkdir -p "${RUN_META_DIR}"
  mkdir -p "${RUN_ARTIFACT_DIR}"
  {
    echo "feedback_e2e_matrix_run_timestamp=${RUN_TS}"
    echo "base_url=${BASE_URL}"
    echo "project=${PROJECT}"
    echo "mode=${MATRIX_MODE}"
    echo "strict_no_skip_critical=${STRICT_NO_SKIP_CRITICAL}"
    echo "pid=$$"
    echo "git_branch=${git_branch}"
    echo "git_commit=${git_commit}"
    echo "guard_package_hash_start=${package_hash_start:-missing}"
    echo "guard_playwright_hash_start=${playwright_hash_start:-missing}"
    echo "exit_code=${exit_code}"
    echo "total_duration_seconds=${matrix_elapsed_local}"
    echo "tests_total=${#TESTS[@]}"
    echo "artifact_dir=${RUN_ARTIFACT_DIR}"
    echo "matrix_log_file=${MATRIX_LOG_FILE}"
    echo "tests:"
    for test_file in "${TESTS[@]}"; do
      echo "  - name=${test_file};status=${STATUS[${test_file}]:-NOT_RUN};duration_seconds=${DURATION[${test_file}]:-0};console_log=${TEST_LOG[${test_file}]:-none};json_report=${TEST_REPORT[${test_file}]:-none}"
    done
  } > "${RUN_META_FILE}"

  echo "Run metadata written: ${RUN_META_FILE}"
}

is_critical_test() {
  local candidate="$1"
  for critical in "${CRITICAL_TESTS[@]}"; do
    if [[ "${critical}" == "${candidate}" ]]; then
      return 0
    fi
  done
  return 1
}

capture_test_attachments() {
  local json_report_path="$1"
  local test_artifact_dir="$2"
  node -e '
    const fs = require("fs");
    const path = require("path");
    const reportPath = process.argv[1];
    const outDir = process.argv[2];
    if (!fs.existsSync(reportPath)) process.exit(0);
    const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
    const copied = [];

    function walk(node) {
      if (!node || typeof node !== "object") return;
      if (Array.isArray(node)) {
        node.forEach(walk);
        return;
      }
      if (Array.isArray(node.attachments)) {
        for (const att of node.attachments) {
          if (!att || !att.path) continue;
          const src = att.path;
          if (!fs.existsSync(src)) continue;
          const srcParent = path.basename(path.dirname(src));
          const destName = `${srcParent}__${path.basename(src)}`;
          const dest = path.join(outDir, destName);
          fs.copyFileSync(src, dest);
          copied.push({
            name: att.name || "attachment",
            contentType: att.contentType || "unknown",
            source: src,
            copiedTo: dest,
          });
        }
      }
      for (const key of Object.keys(node)) walk(node[key]);
    }

    fs.mkdirSync(outDir, { recursive: true });
    walk(report);
    fs.writeFileSync(
      path.join(outDir, "attachments-manifest.json"),
      JSON.stringify({ reportPath, copied }, null, 2)
    );
  ' "${json_report_path}" "${test_artifact_dir}"
}

acquire_lock() {
  if [[ -f "${LOCK_FILE}" ]]; then
    existing_pid="$(cat "${LOCK_FILE}" 2>/dev/null || true)"
    if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
      echo "FATAL: matrix already running (pid=${existing_pid})."
      echo "Hint: wait for current run to finish, or remove stale lock if process is gone."
      exit 4
    fi
    echo "WARN: removing stale lock file ${LOCK_FILE}"
    rm -f "${LOCK_FILE}"
  fi
  echo "$$" > "${LOCK_FILE}"
}

release_lock() {
  if [[ -f "${LOCK_FILE}" ]]; then
    rm -f "${LOCK_FILE}"
  fi
}

if [[ "${MATRIX_MODE}" == "release" ]]; then
  TESTS=(
    "feedback-real-ui-strict.e2e.ts"
    "pm-user-stories-comprehensive.e2e.ts"
  )
  CRITICAL_TESTS=(
    "feedback-real-ui-strict.e2e.ts"
    "pm-user-stories-comprehensive.e2e.ts"
  )
elif [[ "${MATRIX_MODE}" == "full" ]]; then
  TESTS=(
    "feedback-regression.e2e.ts"
    "feedback-branches-deterministic.e2e.ts"
    "feedback-real-ui-strict.e2e.ts"
    "real-user-visual-evaluation.e2e.ts"
    "pm-user-stories-comprehensive.e2e.ts"
  )
  CRITICAL_TESTS=(
    "feedback-real-ui-strict.e2e.ts"
    "pm-user-stories-comprehensive.e2e.ts"
  )
else
  echo "FATAL: unsupported FEEDBACK_MATRIX_MODE='${MATRIX_MODE}' (expected: full|release)"
  exit 5
fi

declare -A STATUS
declare -A DURATION
declare -A TEST_LOG
declare -A TEST_REPORT

overall_rc=0
matrix_start="$(date +%s)"

acquire_lock
trap 'rc=$?; release_lock; write_run_metadata "${rc}"' EXIT

preflight_check
mkdir -p "${RUN_ARTIFACT_DIR}"
package_hash_start="$(hash_file "${PACKAGE_JSON}")"
playwright_hash_start="$(hash_file "${PLAYWRIGHT_CONFIG}")"

echo "== BioMate Feedback E2E Matrix =="
echo "Base URL : ${BASE_URL}"
echo "Project  : ${PROJECT}"
echo "Tests    : ${#TESTS[@]}"
echo "Mode     : ${MATRIX_MODE}"
echo "Guard    : package/playwright drift detection enabled"
echo "Guard    : single-run lock enabled"
echo "Guard    : strict no-SKIP for critical suites = ${STRICT_NO_SKIP_CRITICAL}"
echo "Guard    : isolated Playwright outputs = ${USE_ISOLATED_OUTPUTS}"
echo "Artifact : ${RUN_META_FILE}"
echo "Logs     : ${MATRIX_LOG_FILE}"
echo

for test_file in "${TESTS[@]}"; do
  preflight_check
  package_hash_now="$(hash_file "${PACKAGE_JSON}")"
  playwright_hash_now="$(hash_file "${PLAYWRIGHT_CONFIG}")"
  if [[ "${package_hash_now}" != "${package_hash_start}" || "${playwright_hash_now}" != "${playwright_hash_start}" ]]; then
    echo "FATAL: critical test files changed during matrix run."
    echo " - package.json hash: ${package_hash_start} -> ${package_hash_now}"
    echo " - playwright.config.ts hash: ${playwright_hash_start} -> ${playwright_hash_now}"
    echo "Stop external mutations and rerun."
    exit 3
  fi

  echo ">>> Running ${test_file}"
  start_ts="$(date +%s)"
  test_basename="${test_file%.e2e.ts}"
  test_log_file="${RUN_ARTIFACT_DIR}/${test_basename}.console.log"
  test_json_report="${RUN_ARTIFACT_DIR}/${test_basename}.results.json"
  test_artifact_dir="${RUN_ARTIFACT_DIR}/${test_basename}.artifacts"

  if [[ "${USE_ISOLATED_OUTPUTS}" == "true" ]]; then
    BIOMATE_URL="${BASE_URL}" bash "${ROOT_DIR}/scripts/run-e2e-isolated.sh" "${test_file}" --project "${PROJECT}" 2>&1 | tee "${test_log_file}" | tee -a "${MATRIX_LOG_FILE}"
  else
    BIOMATE_URL="${BASE_URL}" npx playwright test "${test_file}" --project "${PROJECT}" 2>&1 | tee "${test_log_file}" | tee -a "${MATRIX_LOG_FILE}"
  fi
  rc=${PIPESTATUS[0]}
  TEST_LOG["${test_file}"]="${test_log_file}"
  if [[ -f "${ROOT_DIR}/e2e/reports/results.json" ]]; then
    cp "${ROOT_DIR}/e2e/reports/results.json" "${test_json_report}"
    TEST_REPORT["${test_file}"]="${test_json_report}"
    capture_test_attachments "${test_json_report}" "${test_artifact_dir}"
  else
    TEST_REPORT["${test_file}"]="missing"
  fi

  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))

  DURATION["${test_file}"]="${elapsed}"
  if [[ ${rc} -eq 0 ]]; then
    STATUS["${test_file}"]="PASS"
    echo ">>> PASS ${test_file} (${elapsed}s)"
  else
    STATUS["${test_file}"]="FAIL"
    echo ">>> FAIL ${test_file} (${elapsed}s)"
    overall_rc=1
  fi

  if [[ "${STRICT_NO_SKIP_CRITICAL}" == "true" ]] && is_critical_test "${test_file}"; then
    if grep -q "SKIP:" "${test_log_file}"; then
      echo ">>> FAIL ${test_file} (${elapsed}s) due to SKIP lines in critical suite"
      STATUS["${test_file}"]="FAIL_SKIP"
      overall_rc=1
    fi
  fi
  echo
done

matrix_end="$(date +%s)"
matrix_elapsed=$((matrix_end - matrix_start))

echo "== Feedback E2E Matrix Summary =="
for test_file in "${TESTS[@]}"; do
  printf "%-42s  %-4s  %4ss\n" "${test_file}" "${STATUS[${test_file}]}" "${DURATION[${test_file}]}"
done
echo "Total duration: ${matrix_elapsed}s"

if [[ ${overall_rc} -ne 0 ]]; then
  echo "Result: FAILURE"
  exit 1
fi

echo "Result: SUCCESS"
exit 0
