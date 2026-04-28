#!/usr/bin/env bash
# Record all reference-design tutorial demos.
# Each demo loads the Claude reference design at http://localhost:7779 and
# records a .webm video via Playwright.
#
# Usage:
#   ./e2e/run-ref-demos.sh               # all reference demos
#   ./e2e/run-ref-demos.sh 09a 09b       # specific demos
#   ./e2e/run-ref-demos.sh --no-video    # screenshots only

set -uo pipefail
cd "$(dirname "$0")/.."   # repo root = frontend/

NO_VIDEO=false
FILTER=()

for arg in "$@"; do
  if [[ "$arg" == "--no-video" ]]; then
    NO_VIDEO=true
  else
    FILTER+=("$arg")
  fi
done

# All reference demos in order
ALL_DEMOS=(
  "demo-ref-overview"
  "demo-ref-09a-normal-run"
  "demo-ref-09b-qc-autoloop"
  "demo-ref-09c-blocking-errors"
  "demo-ref-09d-cryosparc"
  "demo-ref-09e-disambiguation"
  "demo-ref-A01-nfcore-idle"
  "demo-ref-A04-nfcore-failed"
  "demo-ref-A08-nfcore-watcher"
  "demo-ref-B01-gatk-idle"
  "demo-ref-B02-gatk-running"
  "demo-ref-B03-gatk-completed"
  "demo-ref-C01-admet"
)

# Filter to requested demos if specified
if [[ ${#FILTER[@]} -gt 0 ]]; then
  SELECTED=()
  for KEY in "${FILTER[@]}"; do
    for D in "${ALL_DEMOS[@]}"; do
      if [[ "$D" == *"$KEY"* ]]; then
        SELECTED+=("$D")
      fi
    done
  done
  ALL_DEMOS=("${SELECTED[@]}")
fi

VIDEO_DIR="e2e/demo-videos-ref"
mkdir -p "$VIDEO_DIR"

echo "=== BioMate Reference Design Demo Recording ==="
echo "Reference URL: http://localhost:7779/cro/Workflow Panel Redesign.html"
echo "Demos: ${#ALL_DEMOS[@]}"
echo "Video: $( $NO_VIDEO && echo 'off' || echo 'on' )"
echo "Output: ${VIDEO_DIR}/"
echo ""

FAILED=()
PASSED=()

for DEMO in "${ALL_DEMOS[@]}"; do
  FILE="e2e/${DEMO}.demo.ts"
  if [[ ! -f "$FILE" ]]; then
    echo "⚠  ${DEMO}: file not found (skipping)"
    continue
  fi

  echo "▶  ${DEMO} ..."

  rm -rf e2e/demo-artifacts 2>/dev/null || true

  if npx playwright test --project=demo "$FILE" 2>&1 | tee "/tmp/${DEMO}.log"; then
    STATUS="PASSED"
    PASSED+=("$DEMO")
  else
    STATUS="FAILED"
    FAILED+=("$DEMO")
  fi

  if ! $NO_VIDEO; then
    # Poll for up to 15s — longer demos take more time to finalize the webm
    WEBM=""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
      sleep 1
      WEBM=$(find e2e/demo-artifacts -name "*.webm" 2>/dev/null | head -1)
      [[ -n "$WEBM" ]] && break
    done
    if [[ -n "$WEBM" ]]; then
      DEST="${VIDEO_DIR}/${DEMO}.webm"
      cp "$WEBM" "$DEST"
      SIZE=$(du -sh "$DEST" | cut -f1)
      echo "$( [[ $STATUS == PASSED ]] && echo '✅' || echo '❌' ) ${DEMO} — ${STATUS}  →  $DEST ($SIZE)"
    else
      echo "$( [[ $STATUS == PASSED ]] && echo '✅' || echo '❌' ) ${DEMO} — ${STATUS}  (no video)"
    fi
  else
    echo "$( [[ $STATUS == PASSED ]] && echo '✅' || echo '❌' ) ${DEMO} — ${STATUS}"
  fi
  echo ""
done

echo "=== Summary ==="
echo "Passed: ${#PASSED[@]} / $((${#PASSED[@]} + ${#FAILED[@]}))"
if ! $NO_VIDEO && [[ -d "$VIDEO_DIR" ]]; then
  echo "Videos:"
  find "$VIDEO_DIR" -name "*.webm" | sort | while read -r f; do
    echo "  $f  ($(du -sh "$f" | cut -f1))"
  done
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo ""
  echo "❌ Failed: ${FAILED[*]}"
  exit 1
else
  echo ""
  echo "✅ All reference demos passed"
fi
