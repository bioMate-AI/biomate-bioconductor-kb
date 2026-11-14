#!/usr/bin/env bash
# Run BioMate publication demos with video recording.
# Videos land in e2e/demo-videos/<demo-name>.webm (stable named files).
#
# Usage:
#   ./e2e/run-demos.sh                    # all 4 demos (skips 03 — needs CryoSPARC)
#   ./e2e/run-demos.sh 01                 # Demo 1 only
#   ./e2e/run-demos.sh 01 02 04           # Demos 1, 2, 4
#   ./e2e/run-demos.sh --no-video 01      # screenshots only, no video
#
# Environment:
#   BIOMATE_URL      — server URL (default: http://localhost:5000)
#   E2E_TEST_TOKEN   — bypass token (default: biomate-e2e-bypass-token-dev-only)

set -uo pipefail
cd "$(dirname "$0")/.."   # repo root = frontend/

NO_VIDEO=false
DEMOS=()

for arg in "$@"; do
  if [[ "$arg" == "--no-video" ]]; then
    NO_VIDEO=true
  elif [[ "$arg" =~ ^[A-Za-z]*[0-9]+$ ]]; then
    # Accept digit-only (01, 02, …) and prefixed (T01, T02, …) demo IDs
    DEMOS+=("$arg")
  fi
done

# Default: run demos 1, 2, 4, 5, 6, 11 (skip 3 — requires real CryoSPARC + S3 data)
# Tier-0 modality demos (T01-T05) opt-in via:  ./run-demos.sh T01 T02 T03 T04 T05
if [[ ${#DEMOS[@]} -eq 0 ]]; then
  DEMOS=(01 02 04 05 06 11)
fi

CONFIG="playwright.demo.config.ts"
if $NO_VIDEO; then
  CONFIG="playwright.config.ts"
fi

# Stable output dir — override with DEMO_OUTPUT_DIR env var to avoid conflicts
VIDEO_DIR="${DEMO_OUTPUT_DIR:-e2e/demo-videos}"
mkdir -p "$VIDEO_DIR"
rm -rf e2e/demo-reports

echo "=== BioMate Demo Recording ==="
echo "Server: ${BIOMATE_URL:-http://localhost:5000}"
echo "Demos:  ${DEMOS[*]}"
echo "Video:  $( $NO_VIDEO && echo 'off' || echo 'on (2560×1440 @2x — Retina 1440p)' )"
echo "Output: ${VIDEO_DIR}/<demo-name>.webm"
echo ""

FAILED=()

for NUM in "${DEMOS[@]}"; do
  DEMO_FILE="e2e/demo-${NUM}-*.demo.ts"
  DEMO_FILES=( $DEMO_FILE )

  if [[ ${#DEMO_FILES[@]} -eq 0 ]] || [[ ! -f "${DEMO_FILES[0]}" ]]; then
    echo "⚠  Demo $NUM: no matching file found (skipping)"
    continue
  fi

  FILE="${DEMO_FILES[0]}"
  NAME="$(basename "$FILE" .demo.ts)"
  echo "▶  Running $NAME ..."

  # Playwright writes artifacts to e2e/demo-artifacts/ (per playwright.demo.config.ts).
  # Clear only the artifacts dir before each run so we can locate the new .webm.
  rm -rf e2e/demo-artifacts 2>/dev/null || true
  sleep 1

  if npx playwright test --config="$CONFIG" "$FILE" 2>&1 | tee "/tmp/demo-${NUM}.log"; then
    STATUS="PASSED"
  else
    STATUS="FAILED"
    FAILED+=("$NAME")
  fi

  # Copy the video to a stable named location immediately so it survives the next run
  if ! $NO_VIDEO; then
    sleep 2  # let Playwright finalize the webm
    WEBM=$(find e2e/demo-artifacts -name "*.webm" 2>/dev/null | head -1)
    if [[ -n "$WEBM" ]]; then
      DEST="${VIDEO_DIR}/${NAME}.webm"
      cp "$WEBM" "$DEST"
      SIZE=$(du -sh "$DEST" | cut -f1)
      echo "$( [[ $STATUS == PASSED ]] && echo '✅' || echo '❌' ) $NAME — $STATUS  →  $DEST ($SIZE)"
    else
      echo "$( [[ $STATUS == PASSED ]] && echo '✅' || echo '❌' ) $NAME — $STATUS  (no video found in e2e/demo-artifacts)"
      find e2e/demo-artifacts -type f 2>/dev/null | head -5
    fi
  else
    echo "$( [[ $STATUS == PASSED ]] && echo '✅' || echo '❌' ) $NAME — $STATUS"
  fi
  echo ""
done

echo "=== Video files ==="
if ! $NO_VIDEO && [[ -d "$VIDEO_DIR" ]]; then
  find "$VIDEO_DIR" -name "*.webm" | while read -r f; do
    echo "  $f  ($(du -sh "$f" | cut -f1))"
  done
fi

echo ""
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "❌ Failed demos: ${FAILED[*]}"
  exit 1
else
  echo "✅ All demos passed"
fi
