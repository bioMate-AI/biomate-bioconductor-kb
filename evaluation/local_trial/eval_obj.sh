#!/bin/bash
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/small/objeval/eval.log"; mkdir -p "$SCRATCH/d" "$SCRATCH/models"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base"; [ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/models_20260919/small/sft_v4_adapter/" "$SCRATCH/d/AD/" --recursive --exclude "checkpoint-*/*" --quiet
aws s3 cp "$S3/eval/objective_eval.jsonl" "$SCRATCH/d/oe.jsonl" --quiet
python3 "$HERE/eval_tasks_objective.py" --base "$BASE" --adapter "" --model base --evalfile "$SCRATCH/d/oe.jsonl" --out "$SCRATCH/base.json"
python3 "$HERE/eval_tasks_objective.py" --base "$BASE" --adapter "$SCRATCH/d/AD" --model sft_v4 --evalfile "$SCRATCH/d/oe.jsonl" --out "$SCRATCH/sft.json"
python3 - "$SCRATCH" << 'PY'
import json,sys; S=sys.argv[1]
b=json.load(open(f"{S}/base.json")); s=json.load(open(f"{S}/sft.json"))
tasks=sorted(set(b["per_task"])|set(s["per_task"]))
out={"base_macro":b["macro"],"sft_macro":s["macro"],
     "per_task":{t:{"base":b["per_task"].get(t,{}).get("acc"),"sft":s["per_task"].get(t,{}).get("acc")} for t in tasks}}
json.dump(out,open(f"{S}/objtasks.json","w"),indent=2); print("OBJ_TASKS:",json.dumps(out))
PY
aws s3 cp "$SCRATCH/objtasks.json" "$S3/eval/objective_base_vs_sft.json" --quiet
echo "OBJ_DONE"
