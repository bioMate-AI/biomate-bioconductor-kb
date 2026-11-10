#!/usr/bin/env bash
set -uo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; CODE=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d_%H%M%S); OUT_S3="$S3/eval/spot_traj_$TS"
HF_ID="Qwen/Qwen3.5-9B"; HF_REV="c202236235762e1c871ad0ccb60c8ee5ba337b9a"; PY=/opt/eval-tf/bin/python
mkdir -p "$SCRATCH"/{base,cpt400,cpt800,cpt1200,eval,out}
echo "[entry] OUT_S3=$OUT_S3"
aws s3 cp "$S3/eval/med_today_20261003/openbook.jsonl" "$SCRATCH/eval/openbook.jsonl" --quiet || { echo OPENBOOK_FAIL; exit 11; }
for c in cpt400 cpt800 cpt1200; do aws s3 cp "$S3/eval_staging/$c/" "$SCRATCH/$c/" --recursive --quiet || { echo "${c}_FAIL"; exit 12; }; done
echo "[entry] download base"; PYTHONNOUSERSITE=1 $PY -c "from huggingface_hub import snapshot_download; snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')" || { echo BASE_DL_FAIL; exit 14; }
run(){ echo "[entry] RUN $1"; PYTHONNOUSERSITE=1 $PY "$CODE/spot_cpt800_worker.py" --engine transformers --base "$SCRATCH/base" --rows "$SCRATCH/eval/openbook.jsonl" --adapter "$SCRATCH/$1" --constrain --out "$SCRATCH/out/$1.json"; }
run cpt400; run cpt800; run cpt1200
aws s3 cp "$SCRATCH/out/" "$OUT_S3/" --recursive --quiet
echo "SPOT_TRAJ_DONE out=$OUT_S3"
