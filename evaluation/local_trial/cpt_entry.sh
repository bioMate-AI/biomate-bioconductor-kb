#!/usr/bin/env bash
set -euo pipefail
source /opt/biomate-cpt-venv/bin/activate
export MID_DATA=midtrain_domain_concept.jsonl
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
aws s3 cp /opt/biomate-cpt-venv/requirements.resolved.txt \
  "$S3/spot_logs/$MODEL_SIZE/$STAGE$TAG/requirements.resolved.txt" --quiet
exec bash "$(dirname "$0")/spot_train.sh"
