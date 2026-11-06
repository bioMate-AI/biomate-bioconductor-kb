#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/evalvllmfull/build.log"; mkdir -p "$SCRATCH/d" "$SCRATCH/models"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 20; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base"; [ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/models_20260919/small/sft_v5_adapter/" "$SCRATCH/d/sft_v5/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/spot_ckpt/small/full_v1strong/midtrain/checkpoint-500/" "$SCRATCH/d/mid500/" --recursive --quiet
aws s3 cp "$S3/eval/objective_eval.jsonl" "$SCRATCH/d/oe.jsonl" --quiet
pip3 install -q vllm 2>&1 | tail -1 || pip install -q vllm 2>&1 | tail -1
echo "[vllm] serving base + sft_v5 + mid500"
vllm serve "$BASE" --served-model-name base --enable-lora \
  --lora-modules sft_v5="$SCRATCH/d/sft_v5" mid500="$SCRATCH/d/mid500" \
  --max-lora-rank 16 --dtype bfloat16 --max-model-len 4096 --gpu-memory-utilization 0.9 --port 8000 > "$SCRATCH/vllm.log" 2>&1 &
for i in $(seq 1 90); do curl -s -m 3 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 10; done
curl -s -m 5 http://localhost:8000/health >/dev/null 2>&1 && echo "[vllm] ready" || { echo "[vllm] FAILED"; tail -40 "$SCRATCH/vllm.log"; exit 9; }
python3 "$HERE/eval_vllm.py" --models base,sft_v5,mid500 --evalfile "$SCRATCH/d/oe.jsonl" --out "$SCRATCH/eval_arms_vllm_full.json"
aws s3 cp "$SCRATCH/eval_arms_vllm_full.json" "$S3/eval/eval_arms_vllm_full.json" --quiet
echo "EVALVLLM_DONE"
