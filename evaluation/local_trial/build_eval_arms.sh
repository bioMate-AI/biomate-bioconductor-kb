#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/evalarms/build.log"; mkdir -p "$SCRATCH/data" "$SCRATCH/ad"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base_small"
[ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/eval/gold_routing_eval.jsonl" "$SCRATCH/data/gold.jsonl" --quiet
aws s3 cp "$S3/models_20260919/small/sft_v5_adapter/" "$SCRATCH/ad/sft_v5/" --recursive --quiet
aws s3 cp "$S3/spot_ckpt/small/full_v1strong/midtrain/checkpoint-500/" "$SCRATCH/ad/mid500/" --recursive --quiet
echo "adapters: sft_v5=$(ls "$SCRATCH/ad/sft_v5/" | wc -l) files, mid500=$(ls "$SCRATCH/ad/mid500/" | wc -l) files"
python3 "$HERE/eval_gold.py" --base "$BASE" --model base   --evalfile "$SCRATCH/data/gold.jsonl" --out "$SCRATCH/data/r_base.json"
python3 "$HERE/eval_gold.py" --base "$BASE" --adapter "$SCRATCH/ad/sft_v5" --model sft_v5 --evalfile "$SCRATCH/data/gold.jsonl" --out "$SCRATCH/data/r_sft_v5.json"
python3 "$HERE/eval_gold.py" --base "$BASE" --adapter "$SCRATCH/ad/mid500" --model mid500 --evalfile "$SCRATCH/data/gold.jsonl" --out "$SCRATCH/data/r_mid500.json"
python3 -c "import json; res=[json.load(open(f'$SCRATCH/data/r_{m}.json')) for m in ['base','sft_v5','mid500']]; open('$SCRATCH/data/eval_arms_result.json','w').write(json.dumps(res,indent=2)); print('EVAL ARMS:'); [print(f\"  {r['model']:8s} accept={r['accept_set_accuracy']} exact={r['exact_gold_accuracy']}\") for r in res]"
aws s3 cp "$SCRATCH/data/eval_arms_result.json" "$S3/eval/eval_arms_result.json" --quiet
echo "EVALARMS_UPLOADED"
