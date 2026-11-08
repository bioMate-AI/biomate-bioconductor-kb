#!/bin/bash
# Full on-prem LLM pipeline for ONE model size: mid-train -> merge -> SFT -> merge -> eval -> upload.
# Run twice for the two-model comparison:
#   MODEL_SIZE=small bash gpu_run_pipeline.sh
#   MODEL_SIZE=large bash gpu_run_pipeline.sh
# Same data, same steps -> the only variable is capacity. Grounded DPO is a separate stage (below).
set -euo pipefail
SIZE=${MODEL_SIZE:-large}
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
DATE=${DATE:-20260918}
HERE=$(cd "$(dirname "$0")" && pwd)

# same family -> shared tokenizer/chat template -> a valid small-vs-large comparison and a clean cascade
case "$SIZE" in
  small) HF=Qwen/Qwen3.8-4B  ; MID_STEPS=400 ; SFT_STEPS=400 ; SEQ=2048 ; LORA_R=16 ;;
  large) HF=Qwen/Qwen3.8-27B ; MID_STEPS=800 ; SFT_STEPS=600 ; SEQ=2048 ; LORA_R=32 ;;
  *) echo "MODEL_SIZE must be small|large"; exit 1 ;;
esac
BASE="$SCRATCH/models/base_$SIZE"
OUT="$SCRATCH/out/$SIZE"; mkdir -p "$OUT"

echo "=== [$SIZE] download base $HF ==="
python3 -c "from huggingface_hub import snapshot_download; snapshot_download('$HF', local_dir='$BASE')"

echo "=== [$SIZE] STAGE 1: mid-training (continued pretraining, packed, all-token loss) ==="
python3 "$HERE/midtrain_run.py" --base "$BASE" --data "$SCRATCH/data/midtrain_all.jsonl" \
  --out "$OUT/midtrain" --max-steps $MID_STEPS --seq-len $SEQ --lora-r $LORA_R
# (add --replay <general.jsonl> --replay-frac 0.6 once a general-replay file is staged; see mid-train sweep)

echo "=== [$SIZE] merge mid-train adapter -> domain-adapted base ==="
python3 "$HERE/merge_lora.py" --base "$BASE" --adapter "$OUT/midtrain" --out "$OUT/base_domain"

echo "=== [$SIZE] STAGE 2: SFT on the 17k enriched set (assistant-only loss) ==="
python3 "$HERE/train_qlora_pilot.py" --base "$OUT/base_domain" --data "$SCRATCH/data/sft_enriched.jsonl" \
  --out "$OUT/sft" --max-steps $SFT_STEPS --seq-len $SEQ --lora-r $LORA_R

echo "=== [$SIZE] merge SFT adapter -> deployable model ==="
python3 "$HERE/merge_lora.py" --base "$OUT/base_domain" --adapter "$OUT/sft" --out "$OUT/final"

echo "=== [$SIZE] STAGE 3: eval (two-server, no adapter-toggle ambiguity) ==="
# serve base_domain and final on two ports, compare with the vLLM harness
python3 -m vllm.entrypoints.openai.api_server --model "$OUT/base_domain" --port 8001 &>/tmp/vllm_base.log &
python3 -m vllm.entrypoints.openai.api_server --model "$OUT/final"       --port 8002 &>/tmp/vllm_sft.log &
sleep 90  # model load
python3 "$HERE/eval_holdout_vllm.py" --holdout "$SCRATCH/data/holdout.jsonl" \
  --base-model "$OUT/base_domain" --sft-model "$OUT/final" \
  --url http://127.0.0.1:8002/v1/chat/completions --out "$OUT/eval_$SIZE.json" || true
pkill -f vllm.entrypoints || true

echo "=== [$SIZE] upload artifacts ==="
aws s3 cp "$OUT/sft/"        "$S3/models_${DATE}/$SIZE/sft_adapter/" --recursive --quiet
aws s3 cp "$OUT/eval_$SIZE.json" "$S3/models_${DATE}/$SIZE/eval_$SIZE.json" --quiet
# final merged model is large; upload only if you need it served elsewhere:
# aws s3 cp "$OUT/final/" "$S3/models_${DATE}/$SIZE/final/" --recursive --quiet
echo "PIPELINE_DONE size=$SIZE  eval=$OUT/eval_$SIZE.json"
