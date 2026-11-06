#!/usr/bin/env bash
# stage_flagship_coverage_sweep.sh — STAGED, GATED sweep to CLOSE the open-flagship matrix.
#
# Two remaining gaps (everything addable offline is already surfaced):
#   1) GLM-5.3-prime  — missing the 3 DrugDev columns (pbpk / boin / dd)
#   2) DeepSeek v4.1-flash (small) — missing the WHOLE RealBio leaderboard suite
# Uses the reliable per-task path (run_baseline.py --model → results/<slug>/<task>.jsonl, which
# regen_leaderboard_csv.py scores). Costs real OpenRouter $.
#
# !!! DRY BY DEFAULT — only PRINTS. To run:  EXECUTE=1 bash scripts/stage_flagship_coverage_sweep.sh
# !!! Step 0 (slug confirm) must pass FIRST.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PE="$ROOT/evaluation/datasets/public_export"
OR="https://openrouter.ai/api/v1"
EXECUTE="${EXECUTE:-0}"

run() { echo "+ $*"; if [ "$EXECUTE" = "1" ]; then ( "$@" ); else echo "  (dry; EXECUTE=1 to run)"; fi; }
baseline() {  # baseline <slug> <task> [extra args...]
  run bash -c "cd '$PE' && python3 run_baseline.py $2 --model '$1' --base-url '$OR' --key-env OPENROUTER_API_KEY ${*:3}"
}

echo "=== flagship coverage sweep (EXECUTE=$EXECUTE) ==="

echo; echo "# Step 0 — confirm slugs AND DISCOVER small variants of every open family"
echo "#  (resolves 'does a small GLM/Kimi exist?' — only the live /models list can answer; no guessing)."
run bash -c "cd '$PE' && python3 run_all.py --list-provider-models --base-url '$OR' --key-env OPENROUTER_API_KEY | grep -iE 'glm|kimi|deepseek|qwen|gemma'"
echo "#  → from that output, note any SMALL slug (air/flash/mini/lite/small/-4b/-7b/-9b/-12b);"
echo "#    sweep each discovered small model with the baseline loop below (same as gemma/flash)."

echo; echo "# 1) GLM-5.3-prime — the 3 missing DrugDev tasks"
for t in pbpk_benchmark boin_benchmark drug_discovery_e2e; do baseline "z-ai/glm-5.3-prime" "$t"; done

echo; echo "# 2) DeepSeek v4.1-flash — full RealBio leaderboard suite"
baseline "deepseek/deepseek-v4.1-flash" cross_domain_routing --mode bare
baseline "deepseek/deepseek-v4.1-flash" cross_domain_routing --mode catalog --catalog-style described --wf-db "'$ROOT/backend/database/galaxy_ai_tools.db'"
for t in autofix_benchmark param_prefill workflow_generation protocol_thresholds pbpk_benchmark boin_benchmark drug_discovery_e2e; do
  baseline "deepseek/deepseek-v4.1-flash" "$t"
done

echo; echo "# 2b) gemma-4-31b (small-open, Google) — rostered but never run; full RealBio suite"
baseline "google/gemma-4-31b" cross_domain_routing --mode bare
baseline "google/gemma-4-31b" cross_domain_routing --mode catalog --catalog-style described --wf-db "'$ROOT/backend/database/galaxy_ai_tools.db'"
for t in autofix_benchmark param_prefill workflow_generation protocol_thresholds pbpk_benchmark boin_benchmark drug_discovery_e2e; do
  baseline "google/gemma-4-31b" "$t"
done
echo "#  (+ sweep any small GLM/Kimi discovered in Step 0 with the same baseline loop.)"

echo; echo "# 3) Surface v4.1-flash + gemma on the leaderboard (offline, after their sweep):"
echo "#   add to regen_leaderboard_csv.py MODELS:  (\"DeepSeek V4.1-flash\", \"deepseek_deepseek-v4.1-flash\", {})"
echo "#   and:                                     (\"Gemma-4-31B\", \"google_gemma-4-31b\", {})"
echo "#   (GLM-5.3-prime is already in MODELS — its DrugDev cells fill once the files above exist.)"

echo; echo "# 4) Regenerate D1 + refresh D3/D4 (offline, after the sweeps land)"
run bash -c "cd '$PE' && python3 regen_leaderboard_csv.py && python3 build_5d_leaderboard.py"

echo; echo "=== staged. Nothing above ran unless EXECUTE=1. Confirm slugs (step 0) before any paid step. ==="
