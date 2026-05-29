#!/bin/bash
# BioMate vLLM launch script.
#
# Loads the LoRA adapter manifest from EFS, builds the --lora-modules
# argument, starts vLLM, and runs the spot-interruption monitor in parallel.
# Exits non-zero (so the container restarts and the ASG replaces) on
# vLLM crash or interruption-triggered drain.

set -euo pipefail

# Inputs (all overridable via env, with sensible defaults):
ADAPTERS_DIR="${ADAPTERS_DIR:-/mnt/efs/biomate-adapters}"
HF_CACHE_DIR="${HF_CACHE_DIR:-/mnt/efs/biomate-hfcache}"
BASE_MODEL="${BASE_MODEL:-Qwen/Qwen3-8B}"
GPU_MEM_UTIL="${GPU_MEM_UTIL:-0.85}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
MAX_LORAS="${MAX_LORAS:-6}"
MAX_LORA_RANK="${MAX_LORA_RANK:-16}"
VLLM_PORT="${VLLM_PORT:-8000}"

echo "[start-vllm] base=$BASE_MODEL adapters_dir=$ADAPTERS_DIR"

# Build the --lora-modules argument by globbing the adapters directory.
# Each subdir of $ADAPTERS_DIR that contains a `lora_adapter/` becomes a
# named module: dir-name=path. So:
#   /mnt/efs/biomate-adapters/regulatory_llm_v6/lora_adapter
#   /mnt/efs/biomate-adapters/regulatory_llm_v6_acme/lora_adapter
# Become:
#   --lora-modules \
#       regulatory_llm_v6=/mnt/efs/biomate-adapters/regulatory_llm_v6/lora_adapter \
#       regulatory_llm_v6_acme=/mnt/efs/biomate-adapters/regulatory_llm_v6_acme/lora_adapter
LORA_ARGS=()
if [[ -d "$ADAPTERS_DIR" ]]; then
  for dir in "$ADAPTERS_DIR"/*/; do
    [[ -d "$dir/lora_adapter" ]] || continue
    name=$(basename "$dir")
    LORA_ARGS+=("$name=$dir/lora_adapter")
    echo "[start-vllm] adapter: $name"
  done
fi

if [[ ${#LORA_ARGS[@]} -eq 0 ]]; then
  echo "[start-vllm] WARNING: no LoRA adapters discovered under $ADAPTERS_DIR"
  echo "[start-vllm] vLLM will serve base $BASE_MODEL only — no per-org routing"
fi

# Start the spot monitor in the background. It will SIGTERM us when the
# Spot Instance termination notice fires, after draining ALB traffic.
/opt/biomate/spot-monitor.sh &
SPOT_PID=$!

# Build the vLLM command. --enforce-eager skips CUDA graph compile (faster
# cold start, slightly slower per-token — the right trade for our request
# pattern, where cold start matters more than steady-state throughput).
VLLM_CMD=(
  python3 -m vllm.entrypoints.openai.api_server
  --model "$BASE_MODEL"
  --tokenizer "$BASE_MODEL"
  --download-dir "$HF_CACHE_DIR"
  --host 0.0.0.0
  --port "$VLLM_PORT"
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --max-model-len "$MAX_MODEL_LEN"
  --quantization bitsandbytes
  --enforce-eager
)

if [[ ${#LORA_ARGS[@]} -gt 0 ]]; then
  VLLM_CMD+=(--enable-lora --max-loras "$MAX_LORAS" --max-lora-rank "$MAX_LORA_RANK")
  VLLM_CMD+=(--lora-modules "${LORA_ARGS[@]}")
fi

# Re-emit the command for the boot log (helps debugging from CloudWatch).
echo "[start-vllm] exec: ${VLLM_CMD[*]}"

# Trap so SIGTERM from the spot monitor propagates to vLLM.
trap 'echo "[start-vllm] received SIGTERM; forwarding to vLLM"; kill -TERM $VLLM_PID 2>/dev/null || true' TERM INT

"${VLLM_CMD[@]}" &
VLLM_PID=$!

wait "$VLLM_PID"
RC=$?
echo "[start-vllm] vLLM exited rc=$RC"

# If we still have the spot monitor around, signal it to clean up.
kill "$SPOT_PID" 2>/dev/null || true

exit $RC
