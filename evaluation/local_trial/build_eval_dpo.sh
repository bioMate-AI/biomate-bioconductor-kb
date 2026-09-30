#!/bin/bash
# Eval dpo_v5 (LoRA on sft_v5_merged) + re-confirm sft_v5, on routing + full 17-task.
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/evaldpo/build.log"; mkdir -p "$SCRATCH/d"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 20; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
MERGED="$SCRATCH/models/sft_v5_merged"
aws s3 cp "$S3/models_20260919/small/sft_v5_merged/" "$MERGED/" --recursive --quiet
aws s3 cp "$S3/models_20260919/small/dpo_v5_adapter/" "$SCRATCH/d/dpo_v5/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/routing_objective.jsonl" "$SCRATCH/d/routing.jsonl" --quiet
aws s3 cp "$S3/eval/objective_eval.jsonl" "$SCRATCH/d/full.jsonl" --quiet
pip3 install -q vllm 2>&1 | tail -1 || pip install -q vllm 2>&1 | tail -1
vllm serve "$MERGED" --served-model-name sft_v5 --enable-lora --lora-modules dpo_v5="$SCRATCH/d/dpo_v5" \
  --max-lora-rank 16 --dtype bfloat16 --max-model-len 4096 --gpu-memory-utilization 0.9 --port 8000 > "$SCRATCH/vllm.log" 2>&1 &
for i in $(seq 1 90); do curl -s -m 3 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 10; done
curl -s -m 5 http://localhost:8000/health >/dev/null 2>&1 && echo "[vllm] ready" || { echo "[vllm] FAILED"; tail -40 "$SCRATCH/vllm.log"; exit 9; }
python3 "$HERE/eval_vllm.py" --models sft_v5,dpo_v5 --evalfile "$SCRATCH/d/routing.jsonl" --out "$SCRATCH/dpo_routing.json"
python3 "$HERE/eval_vllm.py" --models sft_v5,dpo_v5 --evalfile "$SCRATCH/d/full.jsonl" --out "$SCRATCH/dpo_full.json"
aws s3 cp "$SCRATCH/dpo_routing.json" "$S3/eval/eval_dpo_routing.json" --quiet
aws s3 cp "$SCRATCH/dpo_full.json" "$S3/eval/eval_dpo_full.json" --quiet
echo "EVALDPO_DONE"
