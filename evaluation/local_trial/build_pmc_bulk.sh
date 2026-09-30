#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/pmcbulk/build.log"; mkdir -p "$SCRATCH/data"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
pip install -q boto3 2>/dev/null || true
python3 "$HERE/build_pmc_bulk.py" --out "$SCRATCH/data/pmc_fulltext_bulk.jsonl" --n ${PMC_ARTICLES:-8000} --max-tokens ${PMC_MAXTOK:-3000000000}
aws s3 cp "$SCRATCH/data/pmc_fulltext_bulk.jsonl" "$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl" --quiet
echo "PMCBULK_UPLOADED rows=$(wc -l < "$SCRATCH/data/pmc_fulltext_bulk.jsonl")"
