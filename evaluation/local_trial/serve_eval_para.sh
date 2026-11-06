#!/bin/bash
# Paraphrase generalization control: serve base 9B, run names vs described on PARAPHRASED queries
# (same intent, different surface form). If the described-lift survives paraphrasing, it is semantic,
# not lexical echo of the benchmark phrasing. No-think only (fast). Uploads + self-terminates.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
OUT_S3="$S3/routing_eval_20261004"
HF=${HF_OVERRIDE:-Qwen/Qwen3.5-9B}
cd "$SCRATCH/code"
pip install -q vllm openai 2>&1 | tail -2 || true
aws s3 cp "$OUT_S3/routing_prompts_para.json" ./pp.json --quiet
python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$SCRATCH/base')" || exit 11
nohup python3 -m vllm.entrypoints.openai.api_server --model "$SCRATCH/base" --served-model-name base \
  --port 8000 --max-model-len 3072 --gpu-memory-utilization 0.95 --enforce-eager --max-num-seqs 2 > "$SCRATCH/vllm.log" 2>&1 &
ok=0; for i in $(seq 1 90); do curl -sf localhost:8000/v1/models >/dev/null 2>&1 && { ok=1; break; }; sleep 10; done
[ "$ok" = 1 ] || { echo "vLLM down"; tail -30 "$SCRATCH/vllm.log"; aws s3 cp "$SCRATCH/vllm.log" "$OUT_S3/vllm_para.log" --quiet; exit 12; }
echo "[para] running names+described (no-think) on paraphrased queries"
ONLY=both THINK=0 MAXTOK=200 python3 box_run_routing.py ./pp.json ./pp_preds.jsonl http://localhost:8000/v1 base 2>&1 | tee "$SCRATCH/para.log"
aws s3 cp ./pp_preds.jsonl "$OUT_S3/routing_preds_para.jsonl" --quiet
aws s3 cp "$SCRATCH/para.log" "$OUT_S3/para.log" --quiet
echo "PARA_EVAL_DONE"
