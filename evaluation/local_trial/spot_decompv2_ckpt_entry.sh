#!/usr/bin/env bash
# GAP-CLOSER: ckpt-275 ONLY on the held-out decomposition_v2 benchmark — the one number missing from
# the truncated run. Serves base+ckpt275 LoRA via harness_shim (max-new 256 so decomp doesn't ramble
# to the cap), runs decompv2_runner GREEDY then (separately) the verifier RE-RANKER on REAL rollouts.
# Uploads EACH result the instant it is written (greedy before rerank even starts) so nothing is lost.
set -uo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
CODE=$(cd "$(dirname "$0")" && pwd)
PY=/opt/eval-tf/bin/python
TS=$(date +%Y%m%d_%H%M%S)
OUT_S3="$S3/eval/decompv2_ckpt275_$TS"
HF_ID="Qwen/Qwen3.5-9B"; HF_REV="c202236235762e1c871ad0ccb60c8ee5ba337b9a"
PORT=8000; BASEURL="http://127.0.0.1:$PORT/v1"
export OPENAI_API_KEY="local-shim"
echo "[entry] OUT_S3=$OUT_S3"
mkdir -p "$SCRATCH"/{base,sft_decompv2,decompv2,logs}

echo "[entry] pull ckpt275 adapter + benchmark + scorer + wf-db"
aws s3 cp "$S3/eval_staging/sft_decompv2/" "$SCRATCH/sft_decompv2/" --recursive --quiet || { echo SFT_FAIL; exit 13; }
aws s3 cp "$S3/eval/decompv2/decomposition_v2.jsonl" "$SCRATCH/decompv2/decomposition_v2.jsonl" --quiet || { echo BENCH_FAIL; exit 14; }
aws s3 cp "$S3/eval/decompv2/score.py" "$SCRATCH/decompv2/score.py" --quiet || { echo SCORER_FAIL; exit 15; }
aws s3 cp "$S3/eval/harness_payload/galaxy_ai_tools.db" "$SCRATCH/decompv2/galaxy_ai_tools.db" --quiet || { echo DB_FAIL; exit 16; }
BENCH="$SCRATCH/decompv2/decomposition_v2.jsonl"; SCORER="$SCRATCH/decompv2/score.py"; DB="$SCRATCH/decompv2/galaxy_ai_tools.db"

echo "[entry] download base $HF_ID @ $HF_REV"
PYTHONNOUSERSITE=1 $PY -c "from huggingface_hub import snapshot_download; snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')" || { echo BASE_DL_FAIL; exit 17; }

echo "[entry] start shim (base + ckpt275 LoRA, max-new 256)"
PYTHONNOUSERSITE=1 $PY "$CODE/harness_shim.py" --base "$SCRATCH/base" --tokenizer "$SCRATCH/base" \
   --adapter "$SCRATCH/sft_decompv2" --port "$PORT" --max-new 256 > "$SCRATCH/logs/shim_ckpt275.log" 2>&1 &
SHIM_PID=$!
up(){ aws s3 cp "$SCRATCH/logs/" "$OUT_S3/logs/" --recursive --exclude "*" --include "decompv2_*" --include "shim_*" --quiet || true; }
ok=0
for i in $(seq 1 90); do curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok":true' && { ok=1; break; }; sleep 5; done
[ "$ok" = 1 ] || { echo "SHIM_HEALTH_FAIL"; tail -40 "$SCRATCH/logs/shim_ckpt275.log"; kill $SHIM_PID 2>/dev/null; exit 18; }
echo "[entry] shim up (pid $SHIM_PID)"

# (1) GREEDY — then upload immediately (before rerank), so the key number is safe
echo "[entry] decomposition_v2 GREEDY (ckpt275)"
PYTHONNOUSERSITE=1 $PY "$CODE/decompv2_runner.py" --bench "$BENCH" --scorer "$SCORER" \
    --model ckpt275 --base-url "$BASEURL" --key-env OPENAI_API_KEY --max-tokens 256 \
    --preds-out "$SCRATCH/logs/decompv2_preds_ckpt275.jsonl" \
    --score-out "$SCRATCH/logs/decompv2_score_ckpt275.json" 2>&1 | tee -a "$SCRATCH/logs/ckpt275_decompv2.log"
up; echo "[entry] greedy uploaded"

# (2) VERIFIER RE-RANKER on REAL rollouts (N=5 @ T=0.8) — rerank-only; upload immediately after
echo "[entry] decomposition_v2 VERIFIER-RERANK (ckpt275, real samples)"
PYTHONNOUSERSITE=1 $PY "$CODE/decompv2_runner.py" --bench "$BENCH" --scorer "$SCORER" \
    --model ckpt275 --base-url "$BASEURL" --key-env OPENAI_API_KEY --max-tokens 256 \
    --rerank-only --rerank-n 5 --rerank-temp 0.8 --db "$DB" \
    --preds-out "$SCRATCH/logs/decompv2_preds_ckpt275.jsonl" \
    --score-out "$SCRATCH/logs/decompv2_score_ckpt275.json" \
    --rerank-preds-out "$SCRATCH/logs/decompv2_preds_ckpt275_rerank.jsonl" \
    --rerank-score-out "$SCRATCH/logs/decompv2_score_ckpt275_rerank.json" 2>&1 | tee -a "$SCRATCH/logs/ckpt275_decompv2.log"
up; echo "[entry] rerank uploaded"

kill $SHIM_PID 2>/dev/null || true
echo "DECOMPV2_CKPT275_DONE out=$OUT_S3"
