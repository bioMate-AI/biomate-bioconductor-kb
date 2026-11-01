#!/bin/bash
# On-prem dose eval on Spark GB10: serve each model via vLLM and score both dose tiers.
#   original  = stock Qwen3.5-9B               (models/base_med)
#   ours_cpt  = our continued-pretrained model (out/.../base_domain, merged)
#   ours_sft  = our final model = CPT + SFT     (base_domain + sft LoRA)
# Thinking is disabled in the eval requests (speed). Results written as per-item receipts.
set -uo pipefail
ROOT=$HOME/biomate-onprem-train
VLLM=$HOME/vllm_venv/bin/vllm
HERE=$(cd "$(dirname "$0")" && pwd)
DATA=$HERE/dose_data
OUT=$HERE/dose_results; mkdir -p "$OUT"
CKPT=$ROOT/out/med/fuller_20261005
BASE_ORIG=$ROOT/models/base_med
BASE_DOM=$CKPT/base_domain
SFT=$CKPT/sft

serve_and_eval () {
  local served="$1" model_path="$2" eval_models="$4"; local lora_args="$3"
  echo "[serve] $served <- $model_path ${lora_args}"
  # shellcheck disable=SC2086
  # low gpu-memory-utilization: the GB10 is shared; default 0.92 (112GiB) exceeds free memory.
  # enforce-eager skips cudagraph capture (less memory, faster start; fine for a small eval).
  # shellcheck disable=SC2086
  "$VLLM" serve "$model_path" --served-model-name "$served" $lora_args \
    --max-model-len 4096 --gpu-memory-utilization 0.40 --enforce-eager --port 8000 > "$OUT/vllm_$served.log" 2>&1 &
  local VP=$!
  local ok=0
  for i in $(seq 1 180); do curl -s -m3 http://127.0.0.1:8000/health >/dev/null 2>&1 && { ok=1; break; }; sleep 5; done
  if [ $ok -ne 1 ]; then echo "[serve] FAILED health for $served"; tail -40 "$OUT/vllm_$served.log"; kill $VP 2>/dev/null; wait $VP 2>/dev/null; return 1; fi
  echo "[serve] $served ready"
  for m in $eval_models; do
    for tier in hand generated; do
      python3 "$HERE/dose_eval_spark.py" --url http://127.0.0.1:8000/v1/chat/completions \
        --model "$m" --data "$DATA/$tier.jsonl" --tier "$tier" --out "$OUT/${m}_${tier}.json" || echo "[eval] FAILED $m $tier"
    done
  done
  kill $VP 2>/dev/null; wait $VP 2>/dev/null; sleep 5
}

# 1) original stock model
serve_and_eval original "$BASE_ORIG" "" "original"
# 2) our models: CPT base served as ours_cpt, + SFT LoRA exposed as ours_sft
serve_and_eval ours_cpt "$BASE_DOM" "--enable-lora --lora-modules ours_sft=$SFT --max-lora-rank 16" "ours_cpt ours_sft"

echo "=== SUMMARY ==="
for f in "$OUT"/*_hand.json "$OUT"/*_generated.json; do
  [ -f "$f" ] && python3 -c "import json,sys; d=json.load(open('$f')); print(d['model'],d['tier'],'outcome',d['outcome'],'safety',d['safety'],'fidelity',d['fidelity'],'empties',str(d['empties'])+'/'+str(d['n']))"
done
echo "DOSE_SPARK_DONE"
