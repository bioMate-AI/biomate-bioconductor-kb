#!/usr/bin/env bash
# vLLM inference server — runs Qwen3-8B + N LoRA adapters as a single
# OpenAI-compatible endpoint. Phase 1 (this script): on-prem GB10.
# Phase 2 (later): identical command runs on AWS g6.xlarge ASG nodes.
#
# Per-request adapter selection via { "model": "regulatory_llm_v6_acme", ... }.
# Galaxy backend talks to this through VLLM_BASE_URL env in ind_assembly.py.
#
# See docs/20260520_VLLM_SPOT_ONDEMAND_INFRA.md for the full architecture.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config (overridable by env)
# ---------------------------------------------------------------------------
VLLM_IMAGE=${VLLM_IMAGE:-vllm/vllm-openai:latest}
BASE_MODEL=${BASE_MODEL:-Qwen/Qwen3-8B}
PORT=${PORT:-8000}
MAX_LORAS=${MAX_LORAS:-6}
MAX_LORA_RANK=${MAX_LORA_RANK:-16}
GPU_MEM_UTIL=${GPU_MEM_UTIL:-0.85}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-4096}

# Adapter root — production uses an EFS mount, Phase 1 uses the local
# models/ directory.
ADAPTER_ROOT=${ADAPTER_ROOT:-$(cd "$(dirname "$0")/../../../models" && pwd)}
HF_CACHE_DIR=${HF_CACHE_DIR:-$(cd "$(dirname "$0")/../../../models" && pwd)/.hf-cache}

# ---------------------------------------------------------------------------
# Build --lora-modules from the adapter directory
# ---------------------------------------------------------------------------
LORA_ARGS=""
for d in "$ADAPTER_ROOT"/regulatory_llm_*/lora_adapter; do
  [ -d "$d" ] || continue
  name=$(basename "$(dirname "$d")")  # regulatory_llm_v6 or regulatory_llm_v6_acme
  LORA_ARGS="$LORA_ARGS $name=$d"
done

if [ -z "$LORA_ARGS" ]; then
  echo "ERROR: no adapter directories under $ADAPTER_ROOT/regulatory_llm_*/lora_adapter"
  exit 1
fi

echo "[vllm] base model:   $BASE_MODEL"
echo "[vllm] port:         $PORT"
echo "[vllm] adapter root: $ADAPTER_ROOT"
echo "[vllm] adapters:"
for kv in $LORA_ARGS; do echo "  - $kv"; done

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
exec docker run --rm \
  --name biomate-vllm \
  --gpus all --ipc=host \
  --ulimit memlock=-1 --ulimit stack=67108864 \
  -v "$ADAPTER_ROOT:$ADAPTER_ROOT:ro" \
  -v "$HF_CACHE_DIR:/root/.cache/huggingface:rw" \
  -p "$PORT:8000" \
  -e VLLM_API_KEY="${VLLM_API_KEY:-EMPTY}" \
  "$VLLM_IMAGE" \
    --model "$BASE_MODEL" \
    --tokenizer "$BASE_MODEL" \
    --gpu-memory-utilization "$GPU_MEM_UTIL" \
    --max-model-len "$MAX_MODEL_LEN" \
    --enable-lora \
    --max-loras "$MAX_LORAS" \
    --max-lora-rank "$MAX_LORA_RANK" \
    --lora-modules $LORA_ARGS \
    --quantization bitsandbytes \
    --enforce-eager
