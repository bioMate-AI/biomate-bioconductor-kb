#!/usr/bin/env bash
# stage_deepseek_sweep.sh — STAGED, GATED comprehensive DeepSeek benchmark sweep.
#
# Closes the four coverage gaps from docs/20261021_DEEPSEEK_COVERAGE_AUDIT.md:
#   (1) confirm the two slugs, (2) sweep the SMALL model on full RealBio,
#   (3) systematic bare-vs-harness pass, (4) DrugDev decision suite per model.
#
# Matrix: {deepseek-v4-pro (large), deepseek-v4.1-flash (small)}
#         x {bare LLM, +harness} x {RealBio 8 tasks, routing bare/catalog, DrugDev suite}
#
# !!! THIS COSTS REAL OPENROUTER $ AND COMPUTE. It is DRY BY DEFAULT — it only PRINTS the
# !!! commands. To actually run, set EXECUTE=1 explicitly:  EXECUTE=1 bash scripts/stage_deepseek_sweep.sh
# Prereqs: OPENROUTER_API_KEY set; step 0 must confirm the slugs FIRST (fixes any slug drift).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL="$ROOT/evaluation/datasets/public_export"
OR_URL="https://openrouter.ai/api/v1"
NAMES="deepseek-v4-pro,deepseek-v4.1-flash"            # run_all.py --models takes roster NAMES
SLUGS=("deepseek/deepseek-v4-pro" "deepseek/deepseek-v4.1-flash")   # run_baseline.py --model takes SLUGS
EXECUTE="${EXECUTE:-0}"

run() {  # print always; execute only when EXECUTE=1
  echo "+ $*"
  if [ "$EXECUTE" = "1" ]; then ( "$@" ); else echo "  (dry-run; set EXECUTE=1 to run)"; fi
}

echo "=== DeepSeek comprehensive sweep (EXECUTE=$EXECUTE) ==="

echo; echo "# Step 0 — confirm the two slugs against the live OpenRouter list (fixes slug drift)"
run bash -c "cd '$EVAL' && python3 run_all.py --list-provider-models --base-url '$OR_URL' --key-env OPENROUTER_API_KEY | grep -i deepseek"

echo; echo "# Step 1 — BARE RealBio 8-task sweep for BOTH models (gap 2: the small model is missing)"
run bash -c "cd '$EVAL' && python3 run_all.py --models '$NAMES'"

echo; echo "# Step 2 — systematic BARE-vs-HARNESS routing per model (gap 3)"
for SLUG in "${SLUGS[@]}"; do
  run bash -c "cd '$EVAL' && python3 run_baseline.py cross_domain_routing --model '$SLUG' --base-url '$OR_URL' --key-env OPENROUTER_API_KEY --mode bare"
  run bash -c "cd '$EVAL' && python3 run_baseline.py cross_domain_routing --model '$SLUG' --base-url '$OR_URL' --key-env OPENROUTER_API_KEY --mode catalog --catalog-style described"
done

echo; echo "# Step 3 — bioc_method_selection bare-vs-kb matrix (already has deepseek; refresh both models)"
echo "#   see evaluation/datasets/bioc_method_selection/run_bioc_matrix.py (inspect its header for invocation)"

echo; echo "# Step 4 — rescore + regenerate the leaderboard from results/ (no hand-entered cells)"
run bash -c "cd '$EVAL' && python3 regen_leaderboard_csv.py"

echo; echo "# Step 5 — DrugDev decision suite (9 archetypes / 30 tasks), HARNESS path vs live BioMate"
echo "#   NOTE: run_decision_benchmark.py hits the live BioMate agent (base_url), i.e. whatever LLM"
echo "#   BioMate is configured with — a HARNESS run, not a per-model OpenRouter BARE sweep. A per-model"
echo "#   BARE decision sweep needs a small baseline-runner addition (TODO, not faked here)."
run bash -c "cd '$ROOT' && python3 evaluation/runners/run_decision_benchmark.py --dry-run"   # dry even under EXECUTE=1: only lists tasks

echo; echo "=== staged. Nothing above ran unless EXECUTE=1. Confirm slugs (step 0) before any paid step. ==="
