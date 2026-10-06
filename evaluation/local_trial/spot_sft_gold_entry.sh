#!/usr/bin/env bash
# SFT-only entry for the collected-gold 9B run (2026-10-06). Trains a QLoRA SFT adapter DIRECTLY on
# the clean base (NO CPT merge) so the harness eval is apples-to-apples base vs base+SFT and isolates
# the effect of the new task data. Uses the proven pinned venv (today_bootstrap.sh:
# torch2.14.1/transformers5.18/peft0.21/trl1.14.1) so the adapter loads exactly as the eval shim expects.
set -euo pipefail
source /opt/biomate-cpt-venv/bin/activate
export DATASET_NUM_PROC=4 SAVE_STEPS=${SAVE_STEPS:-25} PYTHONUNBUFFERED=1
export HF_REVISION=${HF_REVISION:-c202236235762e1c871ad0ccb60c8ee5ba337b9a}
export MODEL_SIZE=med STAGE=sft
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
aws s3 cp /opt/biomate-cpt-venv/requirements.resolved.txt "$S3/spot_logs/$MODEL_SIZE/$STAGE${TAG}/requirements.resolved.txt" --quiet || true
# spot_train.sh (STAGE=sft) trains train_qlora_pilot.py on the clean base with SFT_DATA and uploads
# the adapter to models_20260919/med/sft${TAG}_adapter/.
bash spot_train.sh
echo "SFT_GOLD_ENTRY_DONE"
