#!/bin/bash
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/small/vllmobj/eval.log"; mkdir -p "$SCRATCH/d" "$SCRATCH/models"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 20; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base"; [ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/models_20260919/small/sft_v4_adapter/" "$SCRATCH/d/AD/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/objective_eval.jsonl" "$SCRATCH/d/oe.jsonl" --quiet
pip3 install -q vllm 2>&1 | tail -2 || pip install -q vllm 2>&1 | tail -2
echo "[vllm] starting server"
vllm serve "$BASE" --served-model-name base --enable-lora --lora-modules sft_v4="$SCRATCH/d/AD" \
  --max-lora-rank 16 --dtype bfloat16 --max-model-len 4096 --gpu-memory-utilization 0.9 --port 8000 > "$SCRATCH/vllm.log" 2>&1 &
for i in $(seq 1 60); do curl -s -m 3 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 10; done
curl -s -m 5 http://localhost:8000/health >/dev/null 2>&1 && echo "[vllm] ready" || { echo "[vllm] FAILED to start"; tail -30 "$SCRATCH/vllm.log"; }
python3 "$HERE/eval_vllm.py" --models base,sft_v4 --evalfile "$SCRATCH/d/oe.jsonl" --out "$SCRATCH/vllm_obj.json"
aws s3 cp "$SCRATCH/vllm_obj.json" "$S3/eval/objective_vllm_base_vs_sft.json" --quiet
echo "VLLM_OBJ_DONE"
