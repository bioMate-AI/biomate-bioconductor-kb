#!/bin/bash
# Eval full_v2mid (base_domain_v2mid + SFT) on the 17-task F1 suite -> compare vs sft_v5 (0.431). Does mid-train help?
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/evalmid/build.log"; mkdir -p "$SCRATCH/d"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 20; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base_v2mid"
aws s3 cp "$S3/models_20260919/small/base_domain_v2mid/" "$BASE/" --recursive --quiet
aws s3 cp "$S3/models_20260919/small/full_v2mid_adapter/" "$SCRATCH/d/full_v2mid/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/objective_eval.jsonl" "$SCRATCH/d/oe.jsonl" --quiet
pip3 install -q vllm 2>&1 | tail -1 || pip install -q vllm 2>&1 | tail -1
vllm serve "$BASE" --served-model-name base_v2mid --enable-lora --lora-modules full_v2mid="$SCRATCH/d/full_v2mid" \
  --max-lora-rank 16 --dtype bfloat16 --max-model-len 4096 --gpu-memory-utilization 0.9 --port 8000 > "$SCRATCH/vllm.log" 2>&1 &
for i in $(seq 1 90); do curl -s -m 3 http://localhost:8000/health >/dev/null 2>&1 && break; sleep 10; done
curl -s -m 5 http://localhost:8000/health >/dev/null 2>&1 && echo "[vllm] ready" || { echo "[vllm] FAILED"; tail -40 "$SCRATCH/vllm.log"; exit 9; }
python3 "$HERE/eval_vllm.py" --models full_v2mid --evalfile "$SCRATCH/d/oe.jsonl" --out "$SCRATCH/eval_midtrain_v2.json"
aws s3 cp "$SCRATCH/eval_midtrain_v2.json" "$S3/eval/eval_midtrain_v2.json" --quiet
echo "EVALMID_DONE"
