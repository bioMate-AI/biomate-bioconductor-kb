#!/usr/bin/env bash
set -euo pipefail
source /opt/biomate-cpt-venv/bin/activate
export MID_DATA=midtrain_domain_concept.jsonl DATASET_NUM_PROC=4 SAVE_STEPS=25 PYTHONUNBUFFERED=1
export HF_REVISION=$(python3 -c 'import json; print(json.load(open("today_model_revision.json"))["revision"])')
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
aws s3 cp /opt/biomate-cpt-venv/requirements.resolved.txt "$S3/spot_logs/$MODEL_SIZE/$STAGE$TAG/requirements.resolved.txt" --quiet
aws s3 cp today_model_revision.json "$S3/spot_logs/$MODEL_SIZE/$STAGE$TAG/model_revision.json" --quiet
bash spot_train.sh
OUT="$SCRATCH/out/$MODEL_SIZE/$STAGE"
mkdir -p "$SCRATCH/eval" "$SCRATCH/literature"
aws s3 cp "$S3/airgap/literature_identified_20261003/" "$SCRATCH/literature/" --recursive --quiet
(cd "$SCRATCH/literature" && sha256sum -c SHA256SUMS)
python3 eval_today.py --prepare --base unused --rows eval_today_frozen.jsonl \
  --index "$SCRATCH/literature/literature.sqlite" --out "$SCRATCH/eval/openbook.jsonl"
aws s3 cp "$SCRATCH/eval/openbook.jsonl" "$S3/eval/$MODEL_SIZE$TAG/openbook.jsonl" --quiet
# Each process exits before the next load; baseline uses ORIGINAL weights, not CPT weights.
python3 eval_today.py --base "$SCRATCH/models/base_$MODEL_SIZE" --rows "$SCRATCH/eval/openbook.jsonl" --out "$SCRATCH/eval/base.json"
aws s3 cp "$SCRATCH/eval/base.json" "$S3/eval/$MODEL_SIZE$TAG/base.json" --quiet
python3 eval_today.py --base "$OUT/base_domain" --adapter "$OUT/sft" --rows "$SCRATCH/eval/openbook.jsonl" --out "$SCRATCH/eval/domainpro.json"
aws s3 cp "$SCRATCH/eval/domainpro.json" "$S3/eval/$MODEL_SIZE$TAG/domainpro.json" --quiet
echo TODAY_TRAIN_AND_MCQA_EVAL_DONE
