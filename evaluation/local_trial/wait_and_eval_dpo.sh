#!/bin/bash
set -uo pipefail; cd "$(dirname "$0")"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
echo "waiting for dpo_v5_adapter..."
for i in $(seq 1 90); do
  aws s3 ls "$S3/models_20260919/small/dpo_v5_adapter/adapter_config.json" >/dev/null 2>&1 && { echo "dpo adapter landed -> launching eval"; exec bash run_eval_dpo.sh; }
  sleep 120
done
echo "timed out waiting for dpo adapter"; exit 4
