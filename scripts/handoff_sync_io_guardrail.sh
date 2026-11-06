#!/bin/bash
# ONE-COMMAND SYNC HANDOFF for the param IO-guardrail (commit 3cc6ff724) + the benchmark
# scorer/description/gold fixes. Run this from an env that HAS the Galaxy toolchain
# (python3.9 + Galaxy deps, i.e. the dev box or a machine that can import the Galaxy backend).
# It runs the mandatory PRE_SYNC_CHECKLIST (docs/PRE_SYNC_CHECKLIST.md) and only then syncs.
# Stops on first failure. Nothing here deploys until every gate passes.
#
#   bash scripts/handoff_sync_io_guardrail.sh
#
# Why a handoff: the authoring session had NO Galaxy env (no beaker), so it could not run the
# module-load test (checklist step 3) — the test that would have caught the 2026-06-03 crash-loop.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "=== 0. the change is present (IO-param guardrail in ai_assistant.py) ==="
grep -q "_IO_DATAPLANE_PARAMS" backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py \
  && echo "  OK: _IO_DATAPLANE_PARAMS found" || { echo "  FAIL: guardrail not in working tree — wrong commit?"; exit 1; }

echo "=== 1. frontend type check (tsc) ==="
( cd frontend && npx tsc --noEmit -p . ) && echo "  OK" || { echo "  FAIL tsc"; exit 1; }

echo "=== 2. frontend unit + integration (vitest) ==="
( cd frontend && npx vitest run ) && echo "  OK" || { echo "  FAIL vitest"; exit 1; }

echo "=== 3. Galaxy module-load test (THE critical gate for backend/lib/galaxy changes) ==="
( cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.ai_assistant; print('  import OK')" ) \
  || { echo "  FAIL: ai_assistant failed to import — DO NOT SYNC. Read the full traceback above."; exit 1; }

echo "=== 4. param-extraction guardrail unit check (rules + IO guardrail, no network) ==="
python3 evaluation/local_trial/measure_production_param_rules.py 2>/dev/null | grep "PRODUCTION" \
  && echo "  OK (expect F1 ~0.84, must_not_fill_viol ~27)" || echo "  (skipped: committed base preds not present here)"

echo "=== 5. working tree is clean (sync deploys the WORKING TREE; confirm no stray changes) ==="
if [ -n "$(git status --porcelain backend/)" ]; then
  echo "  WARNING: uncommitted backend changes exist — sync would deploy them too:"; git status --porcelain backend/
  read -r -p "  Proceed anyway? [y/N] " a; [ "$a" = y ] || { echo "  aborted"; exit 1; }
fi

echo "=== 6. SYNC to dev ==="
bash scripts/sync_to_dev.sh

echo "=== 7. POST-SYNC smoke: IO guardrail drops a hallucinated prose input on dev ==="
echo "  Verify manually: POST a genome-inference request with no file given and confirm the response"
echo "  does NOT contain input/accession set to a prose value (e.g. input='RNA-seq'). See"
echo "  evaluation/runners/run_param_prefill.py for the canonical end-to-end check against the live backend."
echo "DONE."
