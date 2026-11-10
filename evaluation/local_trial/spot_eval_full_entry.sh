#!/usr/bin/env bash
set -uo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; CODE=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d_%H%M%S); OUT_S3="$S3/eval/spot_fuller_$TS"
HF_ID="Qwen/Qwen3.5-9B"; HF_REV="c202236235762e1c871ad0ccb60c8ee5ba337b9a"; PY=/opt/eval-tf/bin/python
mkdir -p "$SCRATCH"/{base,cpt1200,sft,eval,out}
echo "[entry] OUT_S3=$OUT_S3"
aws s3 cp "$S3/eval/med_today_20261003/openbook.jsonl" "$SCRATCH/eval/openbook.jsonl" --quiet || { echo OPENBOOK_FAIL; exit 11; }
aws s3 cp "$S3/eval_staging/cpt1200/" "$SCRATCH/cpt1200/" --recursive --quiet || { echo CPT1200_FAIL; exit 12; }
aws s3 cp "$S3/eval_staging/sft/"     "$SCRATCH/sft/"     --recursive --quiet || { echo SFT_FAIL; exit 13; }
echo "[entry] download base"; PYTHONNOUSERSITE=1 $PY -c "from huggingface_hub import snapshot_download; snapshot_download('$HF_ID', revision='$HF_REV', local_dir='$SCRATCH/base')" || { echo BASE_DL_FAIL; exit 14; }
run(){ echo "[entry] RUN $1"; PYTHONNOUSERSITE=1 $PY "$CODE/spot_cpt800_worker.py" --engine transformers --base "$SCRATCH/base" --rows "$SCRATCH/eval/openbook.jsonl" "${@:2}"; }
run cpt1200_constrained   --adapter "$SCRATCH/cpt1200" --constrain --out "$SCRATCH/out/cpt1200_constrained.json"
run domainpro_constrained --merge-adapter "$SCRATCH/cpt1200" --adapter "$SCRATCH/sft" --constrain --out "$SCRATCH/out/domainpro_constrained.json"
run domainpro_free        --merge-adapter "$SCRATCH/cpt1200" --adapter "$SCRATCH/sft" --out "$SCRATCH/out/domainpro_free.json"
aws s3 cp "$SCRATCH/out/" "$OUT_S3/" --recursive --quiet
echo "SPOT_FULLER_EVAL_DONE out=$OUT_S3"
