#!/usr/bin/env bash
# GAP-CLOSER: ckpt-275 ONLY (skip base + regression guard — already measured) on the held-out
# decomposition_v2 benchmark. Fixes the truncation that lost the number last time:
#   * --max-new 256 (the 512 cap made the greedy pass run 39 min and eat the budget)
#   * UPLOAD INCREMENTALLY: greedy score+preds are pushed to S3 BEFORE the re-ranker pass starts,
#     so a worker cap can never lose the greedy honest number again.
# Two runner invocations against one served shim:
#   (1) greedy honest metric  -> upload   (2) --rerank-only verifier re-ranker on REAL samples -> upload
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
MAXNEW=${MAXNEW:-256}
echo "[entry] OUT_S3=$OUT_S3 MAXNEW=$MAXNEW"
mkdir -p "$SCRATCH"/{base,sft_ckpt275,payload,decompv2,logs}

echo "[entry] pull ckpt-275 adapter + bench + scorer + db"
aws s3 cp "$S3/eval_staging/sft_decompv2/" "$SCRATCH/sft_ckpt275/" --recursive --quiet || { echo SFT_FAIL; exit 13; }
aws s3 cp "$S3/eval/decompv2/decomposition_v2.jsonl" "$SCRATCH/decompv2/decomposition_v2.jsonl" --quiet || { echo BENCH_FAIL; exit 16; }
aws s3 cp "$S3/eval/decompv2/score.py" "$SCRATCH/decompv2/score.py" --quiet || { echo SCORER_FAIL; exit 17; }
aws s3 cp "$S3/eval/harness_payload/galaxy_ai_tools.db" "$SCRATCH/payload/galaxy_ai_tools.db" --quiet || { echo DB_FAIL; exit 15; }
BENCH="$SCRATCH/decompv2/decomposition_v2.jsonl"; SCORER="$SCRATCH/decompv2/score.py"; DB="$SCRATCH/payload/galaxy_ai_tools.db"

echo "[entry] download base $HF_ID @ $HF_REV"
PYTHONNOUSERSITE=1 $PY -c "from huggingface_hub import snapshot_download; snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')" || { echo BASE_DL_FAIL; exit 19; }

echo "[entry] start shim (ckpt-275 adapter, max-new $MAXNEW)"
PYTHONNOUSERSITE=1 $PY "$CODE/harness_shim.py" --base "$SCRATCH/base" --tokenizer "$SCRATCH/base" \
   --adapter "$SCRATCH/sft_ckpt275" --port "$PORT" --max-new "$MAXNEW" > "$SCRATCH/logs/shim_ckpt275.log" 2>&1 &
SHIM_PID=$!
up(){ aws s3 cp "$1" "$OUT_S3/$(basename "$1")" --quiet && echo "[entry] uploaded $(basename "$1")" || echo "[entry] UPLOAD_FAIL $1"; }
ok=0
for i in $(seq 1 90); do curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok":true' && { ok=1; break; }; sleep 5; done
[ "$ok" = 1 ] || { echo SHIM_HEALTH_FAIL; tail -40 "$SCRATCH/logs/shim_ckpt275.log"; kill $SHIM_PID 2>/dev/null; exit 20; }
echo "[entry] shim up (pid $SHIM_PID)"

GP="$SCRATCH/logs/decompv2_preds_ckpt275.jsonl";  GS="$SCRATCH/logs/decompv2_score_ckpt275.json"
RP="$SCRATCH/logs/decompv2_preds_ckpt275_rerank.jsonl"; RS="$SCRATCH/logs/decompv2_score_ckpt275_rerank.json"

echo "[entry] (1) GREEDY honest metric"
PYTHONNOUSERSITE=1 $PY "$CODE/decompv2_runner.py" --bench "$BENCH" --scorer "$SCORER" \
  --model ckpt275 --base-url "$BASEURL" --key-env OPENAI_API_KEY \
  --preds-out "$GP" --score-out "$GS" --max-tokens "$MAXNEW" 2>&1 | tee -a "$SCRATCH/logs/ckpt275_greedy.log"
# PERSIST greedy BEFORE the re-ranker pass — a cap can no longer lose it
up "$GS"; up "$GP"; up "$SCRATCH/logs/ckpt275_greedy.log"

echo "[entry] (2) VERIFIER RE-RANKER on REAL samples (rerank-only, N=5 T=0.8)"
PYTHONNOUSERSITE=1 $PY "$CODE/decompv2_runner.py" --bench "$BENCH" --scorer "$SCORER" \
  --model ckpt275 --base-url "$BASEURL" --key-env OPENAI_API_KEY \
  --preds-out "$GP" --score-out "$GS" --max-tokens "$MAXNEW" \
  --rerank-only --rerank-n 5 --rerank-temp 0.8 --db "$DB" \
  --rerank-preds-out "$RP" --rerank-score-out "$RS" 2>&1 | tee -a "$SCRATCH/logs/ckpt275_rerank.log"
up "$RS"; up "$RP"; up "$SCRATCH/logs/ckpt275_rerank.log"

kill $SHIM_PID 2>/dev/null; sleep 5; kill -9 $SHIM_PID 2>/dev/null || true
echo "DECOMPV2_CKPT275_DONE out=$OUT_S3"
