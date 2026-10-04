#!/bin/bash
# Serve base 9B, run the consolidated prompt set (routing described W=200 orig+para + intent + decomp),
# upload raw outputs, self-terminate. Parsing/scoring done locally after.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
OUT_S3="$S3/routing_eval_20261004"
HF=${HF_OVERRIDE:-Qwen/Qwen3.5-9B}
cd "$SCRATCH/code"
pip install -q vllm openai 2>&1 | tail -2 || true
aws s3 cp "$OUT_S3/all_prompts.json" ./all_prompts.json --quiet
python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$SCRATCH/base')" || exit 11
nohup python3 -m vllm.entrypoints.openai.api_server --model "$SCRATCH/base" --served-model-name base \
  --port 8000 --max-model-len 4096 --gpu-memory-utilization 0.96 --enforce-eager --max-num-seqs 1 > "$SCRATCH/vllm.log" 2>&1 &
ok=0; for i in $(seq 1 90); do curl -sf localhost:8000/v1/models >/dev/null 2>&1 && { ok=1; break; }; sleep 10; done
[ "$ok" = 1 ] || { echo "vLLM down"; tail -40 "$SCRATCH/vllm.log"; aws s3 cp "$SCRATCH/vllm.log" "$OUT_S3/vllm_all.log" --quiet; exit 12; }
echo "[all] running consolidated prompts"
python3 generic_vllm_run.py ./all_prompts.json ./all_raw.jsonl http://localhost:8000/v1 base 2>&1 | tee "$SCRATCH/all.log"
aws s3 cp ./all_raw.jsonl "$OUT_S3/all_raw_base.jsonl" --quiet
aws s3 cp "$SCRATCH/all.log" "$OUT_S3/all.log" --quiet
echo "ALL_EVAL_DONE"
