#!/bin/bash
# Serve the base 9B with vLLM and run the precomputed RealBio routing prompts (names + described),
# upload predictions to S3, then let the instance self-terminate. Cheap confirmation (~200x2 short calls)
# of whether the description-enriched catalog (the harness fix) closes the routing LLM+harness gap.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
OUT_S3="$S3/routing_eval_20261004"
HF=${HF_OVERRIDE:-Qwen/Qwen3.5-9B}
cd "$SCRATCH/code"
echo "[eval] $(date) installing vllm"
pip install -q vllm openai 2>&1 | tail -3 || { echo "[eval] vllm install failed"; }
echo "[eval] pulling prompts"
aws s3 cp "$OUT_S3/routing_prompts.json" ./routing_prompts.json --quiet
echo "[eval] downloading base $HF"
python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$SCRATCH/base')" || { echo "[eval] base dl failed"; exit 11; }
echo "[eval] serving vLLM"
# --enforce-eager: skip CUDA-graph capture (OOM'd on 24GB A10G). The base resolves to a multimodal
# Qwen3_5ForConditionalGeneration (heavier than text-only 9B), so it's run on a 48GB L40S (g6e) where
# weights + KV for the ~2.2k-token described prompt fit comfortably. Params env-tunable.
MML=${MAX_MODEL_LEN:-4096}; GMU=${GPU_MEM_UTIL:-0.90}; MNS=${MAX_NUM_SEQS:-16}
nohup python3 -m vllm.entrypoints.openai.api_server --model "$SCRATCH/base" --served-model-name base \
  --port 8000 --max-model-len "$MML" --gpu-memory-utilization "$GMU" --enforce-eager --max-num-seqs "$MNS" \
  > "$SCRATCH/vllm.log" 2>&1 &
SERVE=$!
echo "[eval] waiting for vLLM health"
ok=0; for i in $(seq 1 90); do curl -sf localhost:8000/v1/models >/dev/null 2>&1 && { ok=1; break; }; sleep 10; done
[ "$ok" = 1 ] || { echo "[eval] vLLM never came up — tail:"; tail -40 "$SCRATCH/vllm.log"; aws s3 cp "$SCRATCH/vllm.log" "$OUT_S3/vllm.log" --quiet; exit 12; }
echo "[eval] running routing prompts"
python3 box_run_routing.py ./routing_prompts.json ./routing_preds.jsonl http://localhost:8000/v1 base 2>&1 | tee "$SCRATCH/eval.log"
echo "[eval] uploading"
aws s3 cp ./routing_preds.jsonl "$OUT_S3/routing_preds_base.jsonl" --quiet
aws s3 cp "$SCRATCH/eval.log" "$OUT_S3/eval.log" --quiet
aws s3 cp "$SCRATCH/vllm.log" "$OUT_S3/vllm.log" --quiet
kill $SERVE 2>/dev/null || true
echo "ROUTING_EVAL_DONE"
