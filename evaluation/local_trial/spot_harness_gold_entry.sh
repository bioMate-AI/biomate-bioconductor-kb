#!/usr/bin/env bash
# RealBio LLM+HARNESS eval for the collected-gold SFT: base vs base+gold-SFT (NO CPT merge, so the
# arm isolates the new task data). Serves each arm via harness_shim.py and runs
# public_export/run_baseline.py + score.py UNCHANGED over: cross_domain_routing (catalog/described),
# param_prefill, litqa2, task_decomposition, findings_probe. Uploads predictions + scores + logs.
set -uo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
CODE=$(cd "$(dirname "$0")" && pwd)
PY=/opt/eval-tf/bin/python
TS=$(date +%Y%m%d_%H%M%S)
OUT_S3="$S3/eval/spot_harness_gold_$TS"
HF_ID="Qwen/Qwen3.5-9B"; HF_REV="c202236235762e1c871ad0ccb60c8ee5ba337b9a"
PORT=8000
BASEURL="http://127.0.0.1:$PORT/v1"
export OPENAI_API_KEY="local-shim"
echo "[entry] OUT_S3=$OUT_S3"

mkdir -p "$SCRATCH"/{base,sft_gold,payload,logs}

echo "[entry] pulling gold adapter + harness payload + wf-db from S3"
aws s3 cp "$S3/eval_staging/sft_gold/" "$SCRATCH/sft_gold/" --recursive --quiet || { echo SFTGOLD_FAIL; exit 13; }
aws s3 cp "$S3/eval/harness_payload_gold/harness_payload.tgz" "$SCRATCH/payload/p.tgz" --quiet || { echo PAYLOAD_FAIL; exit 14; }
aws s3 cp "$S3/eval/harness_payload/galaxy_ai_tools.db"  "$SCRATCH/payload/galaxy_ai_tools.db" --quiet || { echo DB_FAIL; exit 15; }
( cd "$SCRATCH/payload" && tar xzf p.tgz )
PE="$SCRATCH/payload/public_export"
DB="$SCRATCH/payload/galaxy_ai_tools.db"
ls -la "$PE" || { echo PAYLOAD_LAYOUT_FAIL; exit 16; }

echo "[entry] downloading base $HF_ID @ $HF_REV"
PYTHONNOUSERSITE=1 $PY -c "from huggingface_hub import snapshot_download; snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')" || { echo BASE_DL_FAIL; exit 17; }

wait_health () {
  for i in $(seq 1 90); do
    if curl -s "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"ok":true'; then return 0; fi
    sleep 5
  done
  return 1
}

run_task () {  # $1=model_label  $2=task  $3...=extra args
  local m="$1"; local task="$2"; shift 2
  echo "[entry] run_baseline $m / $task $*"
  ( cd "$PE" && PYTHONNOUSERSITE=1 $PY run_baseline.py "$task" --model "$m" \
      --base-url "$BASEURL" --key-env OPENAI_API_KEY "$@" ) 2>&1 | tee -a "$SCRATCH/logs/${m}_${task}.log"
}
score_task () {  # $1=model_label $2=task $3=pred_basename
  local m="$1"; local task="$2"; local pf="$3"
  local pred="$PE/results/${m//\//_}/${pf}"
  if [ -f "$pred" ]; then
    echo "[score] $m / $task"
    ( cd "$PE" && PYTHONNOUSERSITE=1 $PY score.py "$task" "$pred" ) | tee "$SCRATCH/logs/score_${m}_${task}.json"
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
  run_task  "$label" cross_domain_routing --mode catalog --catalog-style described --wf-db "$DB"
  score_task "$label" cross_domain_routing "cross_domain_routing_catalog_described.jsonl"
  run_task  "$label" param_prefill
  score_task "$label" param_prefill "param_prefill.jsonl"
  run_task  "$label" litqa2
  score_task "$label" litqa2 "litqa2.jsonl"
  run_task  "$label" task_decomposition
  score_task "$label" task_decomposition "task_decomposition.jsonl"
  run_task  "$label" findings_probe
  score_task "$label" findings_probe "findings_probe.jsonl"
  echo "[entry] ===== ARM $label : stopping shim ====="
  kill $SHIM_PID 2>/dev/null; sleep 8
  for i in 1 2 3 4 5 6; do curl -s "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 || break; sleep 5; done
  kill -9 $SHIM_PID 2>/dev/null || true
  wait $SHIM_PID 2>/dev/null || true
  sleep 5
  nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null || true
}

run_arm base
run_arm gold --adapter "$SCRATCH/sft_gold"

echo "[entry] uploading predictions + scores + logs"
aws s3 cp "$PE/results/" "$OUT_S3/results/" --recursive --quiet || true
aws s3 cp "$SCRATCH/logs/" "$OUT_S3/logs/" --recursive --quiet || true
[ -f /opt/eval-tf-requirements.txt ] && aws s3 cp /opt/eval-tf-requirements.txt "$OUT_S3/eval-tf-requirements.txt" --quiet
echo "SPOT_HARNESS_GOLD_EVAL_DONE out=$OUT_S3"
