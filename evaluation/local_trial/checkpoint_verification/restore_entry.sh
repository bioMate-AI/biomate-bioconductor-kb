#!/bin/bash
set -euo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
SRC="$S3/spot_ckpt/small/full_concept_recovery2_20261003"
DEST="$S3/spot_logs/small/restore_concept_recovery2_20261003"
mkdir -p "$SCRATCH/restore"
trap 'rc=$?; aws s3 cp "$SCRATCH/restore/restore_report.json" "$DEST/restore_report.json" --only-show-errors || true; exit "$rc"' EXIT
aws s3 sync "$SRC/base_domain/" "$SCRATCH/restore/base_domain/" --only-show-errors
aws s3 sync "$SRC/sft/" "$SCRATCH/restore/sft/" --exclude 'checkpoint-*/*' --exclude '*.bin' --only-show-errors
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$SCRATCH/restore-venv/bin/python" "$(dirname "$0")/verify_restore.py"
