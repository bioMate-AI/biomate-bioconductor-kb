#!/bin/bash
# Determine the mid-train effect NOW from the existing midtrain checkpoint (default 1200), WITHOUT waiting
# for 5000. Matched fast SFT on {plain base} vs {mid-trained base}, eval both on gold routing -> lift.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
STEP=${MID_CKPT:-1200}; SFTN=${SFTN:-300}; SEQ=${SEQ:-1024}
LOGDST="$S3/spot_logs/small/headtohead/eval.log"; mkdir -p "$SCRATCH/models" "$SCRATCH/d"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE="$SCRATCH/models/base"; [ -d "$BASE" ] || python3 -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-4B', local_dir='$BASE')"
aws s3 cp "$S3/sft/multitask_sft_enriched.jsonl" "$SCRATCH/d/sft.jsonl" --quiet
aws s3 cp "$S3/eval/gold_routing_eval.jsonl" "$SCRATCH/d/gr.jsonl" --quiet
# mid-trained base = merge(midtrain checkpoint-STEP)
aws s3 cp "$S3/spot_ckpt/small/full_litkg/midtrain/checkpoint-$STEP/" "$SCRATCH/d/ck/" --recursive --quiet
python3 "$HERE/merge_lora.py" --base "$BASE" --adapter "$SCRATCH/d/ck" --out "$SCRATCH/models/midbase"
# matched SFT on each base
python3 "$HERE/train_qlora_pilot.py" --base "$BASE" --data "$SCRATCH/d/sft.jsonl" --out "$SCRATCH/sftA" --max-steps $SFTN --seq-len $SEQ --batch-size 8 --grad-accum 4
python3 "$HERE/train_qlora_pilot.py" --base "$SCRATCH/models/midbase" --data "$SCRATCH/d/sft.jsonl" --out "$SCRATCH/sftB" --max-steps $SFTN --seq-len $SEQ --batch-size 8 --grad-accum 4
export EVAL_DTYPE=bf16
# OBJECTIVE-ONLY: gold routing accept-set on both arms (NO teacher-coverage judge — proven unreliable)
python3 "$HERE/eval_gold.py" --base "$BASE" --adapter "$SCRATCH/sftA" --model plain --evalfile "$SCRATCH/d/gr.jsonl" --out "$SCRATCH/Ag.json"
python3 "$HERE/eval_gold.py" --base "$SCRATCH/models/midbase" --adapter "$SCRATCH/sftB" --model mid --evalfile "$SCRATCH/d/gr.jsonl" --out "$SCRATCH/Bg.json"
python3 - "$SCRATCH" "$STEP" "$SFTN" << 'PYEOF'
import json, sys
S, step, sftn = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ag=json.load(open(f"{S}/Ag.json")); bg=json.load(open(f"{S}/Bg.json"))
res={"midtrain_ckpt":step,"sft_steps":sftn,"metric":"gold_routing_accept_set (objective, no LLM judge)",
     "plain_sft":ag["accept_set_accuracy"],"mid_sft":bg["accept_set_accuracy"],
     "plain_exact":ag["exact_gold_accuracy"],"mid_exact":bg["exact_gold_accuracy"],
     "lift":round(bg["accept_set_accuracy"]-ag["accept_set_accuracy"],4)}
json.dump(res, open(f"{S}/h2h.json","w"), indent=2)
print("H2H_OBJECTIVE:", json.dumps(res))
PYEOF
aws s3 cp "$SCRATCH/h2h.json" "$S3/eval/headtohead_${STEP}.json" --quiet
echo "H2H_DONE"
