#!/usr/bin/env bash
# Entry for the paired CPT-800 MCQA eval. Pulls inputs once, downloads the base once, then runs the
# worker: vLLM engine first, automatic transformers fallback on any vLLM/LoRA failure (exit 42),
# all on the same box (no relaunch). Uploads results + logs to S3 and prints a SUMMARY line.
set -uo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
CODE=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d_%H%M%S)
OUT_S3="$S3/eval/spot_cpt800_$TS"
HF_ID="Qwen/Qwen3.5-9B"
HF_REV="c202236235762e1c871ad0ccb60c8ee5ba337b9a"
mkdir -p "$SCRATCH/base" "$SCRATCH/adapter" "$SCRATCH/eval"

echo "[entry] OUT_S3=$OUT_S3"

echo "[entry] pulling frozen eval set + adapter from S3"
aws s3 cp "$S3/eval/med_today_20261003/openbook.jsonl" "$SCRATCH/eval/openbook.jsonl" --quiet || { echo "OPENBOOK_PULL_FAIL"; exit 11; }
aws s3 cp "$S3/eval_staging/cpt800/" "$SCRATCH/adapter/" --recursive --quiet || { echo "ADAPTER_PULL_FAIL"; exit 12; }
N=$(wc -l < "$SCRATCH/eval/openbook.jsonl"); echo "[entry] openbook rows=$N (expect 261)"

echo "[entry] downloading base $HF_ID @ $HF_REV"
/opt/eval-tf/bin/python -c "
from huggingface_hub import snapshot_download
p=snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')
print('BASE_DL', p)
" || { echo "BASE_DL_FAIL"; exit 13; }

cd "$CODE"
ENGINE_USED=""
RESULT_JSON="$SCRATCH/eval/results.json"

run_worker () {  # $1 = engine, $2 = python
  echo "[entry] === trying engine: $1 ==="
  "$2" spot_cpt800_worker.py --engine "$1" \
    --base "$SCRATCH/base" --adapter "$SCRATCH/adapter" \
    --rows "$SCRATCH/eval/openbook.jsonl" --out "$RESULT_JSON"
}

VLLM_PY=/opt/eval-vllm/bin/python
if [ -x "$VLLM_PY" ] && "$VLLM_PY" -c "import vllm" 2>/dev/null; then
  if run_worker vllm "$VLLM_PY"; then
    ENGINE_USED=vllm
  else
    echo "[entry] vLLM engine failed/fell back -> transformers"
  fi
else
  echo "[entry] vLLM not importable -> transformers"
fi

if [ -z "$ENGINE_USED" ]; then
  if run_worker transformers /opt/eval-tf/bin/python; then
    ENGINE_USED=transformers
  else
    echo "TRANSFORMERS_ENGINE_FAILED"
  fi
fi

echo "[entry] engine_used=$ENGINE_USED"
# Upload everything (results + env manifests + logs). boot.log is streamed separately by userdata.
[ -f "$RESULT_JSON" ] && aws s3 cp "$RESULT_JSON" "$OUT_S3/results.json" --quiet
aws s3 cp "$SCRATCH/eval/openbook.jsonl" "$OUT_S3/openbook_used.jsonl" --quiet
[ -f /opt/eval-tf-requirements.txt ] && aws s3 cp /opt/eval-tf-requirements.txt "$OUT_S3/eval-tf-requirements.txt" --quiet
[ -f /opt/eval-vllm-requirements.txt ] && aws s3 cp /opt/eval-vllm-requirements.txt "$OUT_S3/eval-vllm-requirements.txt" --quiet
printf '{"engine_used":"%s","ts":"%s","n_rows":%s}\n' "$ENGINE_USED" "$TS" "$N" > "$SCRATCH/eval/meta.json"
aws s3 cp "$SCRATCH/eval/meta.json" "$OUT_S3/meta.json" --quiet

echo "SPOT_CPT800_EVAL_DONE engine=$ENGINE_USED out=$OUT_S3"
