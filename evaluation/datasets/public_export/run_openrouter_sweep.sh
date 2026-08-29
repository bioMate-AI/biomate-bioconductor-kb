#!/usr/bin/env bash
# RealBio cross-system sweep via OpenRouter — frontier + latest open-source.
# Runs each model across the 5 well-posed tasks (routing in both modes). One OpenAI-compatible
# runner, one objective scorer, identical items for every system. Models run in PARALLEL (one bg
# job each); tasks within a model run sequentially to respect per-model rate limits.
set -u
cd "$(dirname "$0")"
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY:?set OPENROUTER_API_KEY}"
BASE="https://openrouter.ai/api/v1"
LOGDIR="${LOGDIR:-/private/tmp/claude-501/-Users-kky-biomate/46c7e29b-b39f-4c97-870e-9e9ba76af59f/scratchpad/openrouter_sweep}"
mkdir -p "$LOGDIR"

MODELS=(
  "openai/gpt-5.6-luna"
  "anthropic/claude-opus-5"
  "google/gemini-3.1-pro-preview"
  "moonshotai/kimi-k3"
  "qwen/qwen3.8-max"
  "deepseek/deepseek-v4-pro"
  "z-ai/glm-5.2"
)

run_model () {
  local M="$1"; local tag="${M//\//_}"; local log="$LOGDIR/$tag.log"
  echo "=== START $M $(date -u +%H:%M:%S) ===" > "$log"
  run () { python3 run_baseline.py "$@" --model "$M" --base-url "$BASE" --key-env OPENROUTER_API_KEY >> "$log" 2>&1; }
  run cross_domain_routing --mode bare
  run cross_domain_routing --mode catalog
  run autofix_benchmark
  run param_prefill
  run workflow_generation
  run protocol_thresholds
  echo "=== DONE $M $(date -u +%H:%M:%S) ===" >> "$log"
}

for M in "${MODELS[@]}"; do run_model "$M" & done
wait
echo "ALL MODELS DONE $(date -u +%H:%M:%S)" > "$LOGDIR/_ALL_DONE"
