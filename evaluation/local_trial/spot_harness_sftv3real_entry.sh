#!/usr/bin/env bash
# RealBio LLM+HARNESS eval for the SFT-V3-REAL retrain: base vs base+sftv3real-SFT (NO CPT merge).
# Per arm (base, then sftv3real), in THIS order so a cap can never lose the headline:
#   (A) decomposition_real  -- THE HEADLINE (out-of-generator: real nf-core/chain/GTN topologies)
#   (B) decomposition_v2    -- comparison vs the prior synthetic win
#   (C) REGRESSION GUARD    -- param_prefill (incl. must_not_fill count!), cross_domain_routing,
#                              litqa2, findings_probe, task_decomposition (old coarse, continuity)
# Each score is UPLOADED TO S3 THE MOMENT IT COMPUTES (the v2 eval lost its tail to a 2h cap because
# it uploaded only at the end — never again). Greedy only (no verifier re-ranker: the re-ranker was
# already validated in v2 §3.3 and is out of scope here; skipping it keeps the box bounded + fast).
# Decomp runner capped at --max-tokens 256 (the 512 cap made the base greedy pass run 39 min in v2).
set -uo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
CODE=$(cd "$(dirname "$0")" && pwd)
PY=/opt/eval-tf/bin/python
TS=$(date +%Y%m%d_%H%M%S)
OUT_S3="$S3/eval/spot_harness_sftv3real_$TS"
HF_ID="Qwen/Qwen3.5-9B"; HF_REV="c202236235762e1c871ad0ccb60c8ee5ba337b9a"
PORT=8000
BASEURL="http://127.0.0.1:$PORT/v1"
export OPENAI_API_KEY="local-shim"
echo "[entry] OUT_S3=$OUT_S3"

mkdir -p "$SCRATCH"/{base,sft_sftv3real,payload,decompreal,decompv2,logs}

up(){ aws s3 cp "$1" "$OUT_S3/$2/$(basename "$1")" --quiet && echo "[entry] UP $2/$(basename "$1")" || echo "[entry] UPLOAD_FAIL $1"; }

echo "[entry] pulling sftv3real adapter + harness payload + wf-db + both benches from S3"
aws s3 cp "$S3/eval_staging/sft_sftv3real/" "$SCRATCH/sft_sftv3real/" --recursive --quiet || { echo SFT_FAIL; exit 13; }
aws s3 cp "$S3/eval/harness_payload_gold/harness_payload.tgz" "$SCRATCH/payload/p.tgz" --quiet || { echo PAYLOAD_FAIL; exit 14; }
aws s3 cp "$S3/eval/harness_payload/galaxy_ai_tools.db"  "$SCRATCH/payload/galaxy_ai_tools.db" --quiet || { echo DB_FAIL; exit 15; }
aws s3 cp "$S3/eval/decompreal/decomposition_real.jsonl" "$SCRATCH/decompreal/decomposition_real.jsonl" --quiet || { echo RBENCH_FAIL; exit 16; }
aws s3 cp "$S3/eval/decompreal/score.py" "$SCRATCH/decompreal/score.py" --quiet || { echo RSCORER_FAIL; exit 17; }
aws s3 cp "$S3/eval/decompv2/decomposition_v2.jsonl" "$SCRATCH/decompv2/decomposition_v2.jsonl" --quiet || { echo V2BENCH_FAIL; exit 18; }
aws s3 cp "$S3/eval/decompv2/score.py" "$SCRATCH/decompv2/score.py" --quiet || { echo V2SCORER_FAIL; exit 19; }
( cd "$SCRATCH/payload" && tar xzf p.tgz )
PE="$SCRATCH/payload/public_export"
DB="$SCRATCH/payload/galaxy_ai_tools.db"
RBENCH="$SCRATCH/decompreal/decomposition_real.jsonl"; RSCORER="$SCRATCH/decompreal/score.py"
V2BENCH="$SCRATCH/decompv2/decomposition_v2.jsonl";     V2SCORER="$SCRATCH/decompv2/score.py"
ls -la "$PE" || { echo PAYLOAD_LAYOUT_FAIL; exit 20; }

echo "[entry] downloading base $HF_ID @ $HF_REV"
PYTHONNOUSERSITE=1 $PY -c "from huggingface_hub import snapshot_download; snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')" || { echo BASE_DL_FAIL; exit 21; }

wait_health () {
  for i in $(seq 1 90); do
    curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok":true' && return 0
    sleep 5
  done
  return 1
}

run_decomp () {  # $1=label $2=bench $3=scorer $4=tag(real|v2)
  local m="$1" bench="$2" scorer="$3" tag="$4"
  local pp="$SCRATCH/logs/decomp_${tag}_preds_${m}.jsonl"
  local ps="$SCRATCH/logs/decomp_${tag}_score_${m}.json"
  echo "[entry] decomposition_${tag} / $m (max-tokens 256)"
  PYTHONNOUSERSITE=1 $PY "$CODE/decompv2_runner.py" --bench "$bench" --scorer "$scorer" \
      --model "$m" --base-url "$BASEURL" --key-env OPENAI_API_KEY \
      --preds-out "$pp" --score-out "$ps" --max-tokens 256 2>&1 | tee -a "$SCRATCH/logs/${m}_decomp_${tag}.log"
  up "$ps" scores; up "$pp" preds        # UPLOAD IMMEDIATELY
}

run_reg () {  # $1=label $2=task $3=predfile $4...=extra run_baseline args
  local m="$1" task="$2" pf="$3"; shift 3
  echo "[entry] run_baseline $m / $task $*"
  ( cd "$PE" && PYTHONNOUSERSITE=1 $PY run_baseline.py "$task" --model "$m" \
      --base-url "$BASEURL" --key-env OPENAI_API_KEY "$@" ) 2>&1 | tee -a "$SCRATCH/logs/${m}_${task}.log"
  local pred="$PE/results/${m//\//_}/${pf}"
  if [ -f "$pred" ]; then
    echo "[score] $m / $task"
    ( cd "$PE" && PYTHONNOUSERSITE=1 $PY score.py "$task" "$pred" ) | tee "$SCRATCH/logs/score_${m}_${task}.json"
    up "$SCRATCH/logs/score_${m}_${task}.json" scores     # UPLOAD IMMEDIATELY
    up "$pred" preds
  else
    echo "[score] MISSING PRED $pred"
  fi
}

run_arm () {  # $1=label  $2...=shim args
  local label="$1"; shift
  echo "[entry] ===== ARM $label : starting shim ====="
  PYTHONNOUSERSITE=1 $PY "$CODE/harness_shim.py" --base "$SCRATCH/base" --tokenizer "$SCRATCH/base" \
     --port "$PORT" --max-new 512 "$@" > "$SCRATCH/logs/shim_${label}.log" 2>&1 &
  local SHIM_PID=$!
  if ! wait_health; then
    echo "[entry] SHIM_${label}_HEALTH_FAIL"; tail -40 "$SCRATCH/logs/shim_${label}.log"
    kill $SHIM_PID 2>/dev/null; return 1
  fi
  echo "[entry] shim up (pid $SHIM_PID)"
  # (A) HEADLINE first, (B) comparison, then (C) regression guard — each uploaded as it computes
  run_decomp "$label" "$RBENCH"  "$RSCORER"  real
  run_decomp "$label" "$V2BENCH" "$V2SCORER" v2
  run_reg "$label" param_prefill        "param_prefill.jsonl"
  run_reg "$label" cross_domain_routing "cross_domain_routing_catalog_described.jsonl" --mode catalog --catalog-style described --wf-db "$DB"
  run_reg "$label" litqa2               "litqa2.jsonl"
  run_reg "$label" findings_probe       "findings_probe.jsonl"
  run_reg "$label" task_decomposition   "task_decomposition.jsonl"
  echo "[entry] ===== ARM $label : stopping shim ====="
  kill $SHIM_PID 2>/dev/null; sleep 8
  for i in 1 2 3 4 5 6; do curl -s "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || break; sleep 5; done
  kill -9 $SHIM_PID 2>/dev/null || true
  wait $SHIM_PID 2>/dev/null || true
  sleep 5
  nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null || true
}

run_arm base
run_arm sftv3real --adapter "$SCRATCH/sft_sftv3real"

echo "[entry] final sweep upload (logs + any stragglers)"
aws s3 cp "$PE/results/" "$OUT_S3/results/" --recursive --quiet || true
aws s3 cp "$SCRATCH/logs/" "$OUT_S3/logs/" --recursive --quiet || true
echo "SPOT_HARNESS_SFTV3REAL_EVAL_DONE out=$OUT_S3"
