#!/usr/bin/env bash
# Production integration script — moves the sandbox IND port into the
# live frontend. Run only after:
#   1. user signs off on .snapshots/e2e/ visual review
#   2. live-backend smoke against Galaxy on :8080 passes (the 4 feedback
#      POSTs actually reach feedback_router.py)
#
# Dry-run by default. Pass --apply to make changes.
#
# What it does:
#   • Copies sandbox files into frontend/client/src/
#   • Rewrites sandbox-relative imports (../components/, ../lib/, ...)
#     to @/-aliases (@/components/ind-report/, @/lib/, ...)
#   • Deletes the legacy 1,984-line frontend/client/src/pages/ind-report.tsx
#   • Verifies tsc clean
#   • Reverts everything on tsc failure

set -euo pipefail

APPLY=${1:-}
SANDBOX="frontend/sandbox/ind-port"
CLIENT="frontend/client/src"

cd "$(git rev-parse --show-toplevel)"

# --- pre-flight ----------------------------------------------------------
[ -d "$SANDBOX" ] || { echo "sandbox $SANDBOX not found"; exit 1; }
[ -d "$CLIENT" ]  || { echo "client $CLIENT not found";   exit 1; }

# --- file moves ----------------------------------------------------------
declare -a MOVES=(
  # src                                          dst
  "$SANDBOX/styles/ind-report.css                $CLIENT/styles/ind-report.css"
  "$SANDBOX/lib/ind-report-api.ts                $CLIENT/lib/ind-report-api.ts"
  "$SANDBOX/components/IndLeftNav.tsx            $CLIENT/components/ind-report/IndLeftNav.tsx"
  "$SANDBOX/components/IndSteps.tsx              $CLIENT/components/ind-report/IndSteps.tsx"
  "$SANDBOX/components/IndDocPanel.tsx           $CLIENT/components/ind-report/IndDocPanel.tsx"
  "$SANDBOX/components/IndOverlays.tsx           $CLIENT/components/ind-report/IndOverlays.tsx"
  "$SANDBOX/components/EditableParagraph.tsx     $CLIENT/components/ind-report/EditableParagraph.tsx"
  "$SANDBOX/pages/IndReportPage.tsx              $CLIENT/pages/ind-report.tsx"
)

# --- legacy file removal -------------------------------------------------
LEGACY="$CLIENT/pages/ind-report.tsx"

# --- import rewrite map --------------------------------------------------
# Sandbox uses ../components/Foo, ../lib/bar, ../styles/baz.
# Production uses @/components/ind-report/Foo, @/lib/bar, @/styles/baz.
declare -a REWRITES=(
  's|"\.\./components/IndLeftNav"|"@/components/ind-report/IndLeftNav"|g'
  's|"\.\./components/IndSteps"|"@/components/ind-report/IndSteps"|g'
  's|"\.\./components/IndDocPanel"|"@/components/ind-report/IndDocPanel"|g'
  's|"\.\./components/IndOverlays"|"@/components/ind-report/IndOverlays"|g'
  's|"\.\./components/EditableParagraph"|"@/components/ind-report/EditableParagraph"|g'
  's|"\.\./lib/ind-report-api"|"@/lib/ind-report-api"|g'
  's|"\.\./styles/ind-report\.css"|"@/styles/ind-report.css"|g'
  # Component-relative imports (e.g. ./IndSteps inside ind-report/) stay as-is.
)

# --- execute -------------------------------------------------------------
echo "[migrate] $([ "$APPLY" = "--apply" ] && echo APPLY || echo DRY-RUN) mode"
echo "[migrate] sandbox: $SANDBOX"
echo "[migrate] client:  $CLIENT"
echo

if [ "$APPLY" = "--apply" ]; then
  mkdir -p "$CLIENT/components/ind-report"
  for entry in "${MOVES[@]}"; do
    read -r src dst <<<"$(echo "$entry" | xargs)"
    echo "  cp $src → $dst"
    cp "$src" "$dst"
  done

  echo "[migrate] rewriting imports in copied files…"
  for entry in "${MOVES[@]}"; do
    read -r src dst <<<"$(echo "$entry" | xargs)"
    [[ "$dst" == *.tsx ]] || [[ "$dst" == *.ts ]] || continue
    for rule in "${REWRITES[@]}"; do
      sed -i -E "$rule" "$dst"
    done
  done

  echo "[migrate] tsc check…"
  (cd frontend && npx tsc --noEmit) || {
    echo "[migrate] tsc failed — reverting"
    git restore -- "$CLIENT"
    exit 1
  }
  echo "[migrate] ✓ tsc clean"

  echo
  echo "[migrate] Done. Review with: git diff $CLIENT"
  echo "[migrate] Next: rm the sandbox once integration is committed."
else
  for entry in "${MOVES[@]}"; do
    read -r src dst <<<"$(echo "$entry" | xargs)"
    [ -f "$src" ] && echo "  would copy $src → $dst"
  done
  echo
  echo "[migrate] would apply $(echo "${REWRITES[*]}" | tr ' ' '\n' | grep -c "^s|") import rewrites"
  echo "[migrate] would replace legacy $LEGACY"
  echo
  echo "[migrate] DRY RUN — re-run with --apply when ready."
fi
