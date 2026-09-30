#!/bin/bash
# PMC full-text at SCALE from AWS Open Data (boto3 UNSIGNED, in-process parallel). Incrementally uploads the
# growing jsonl every 120s so a long run (100k-500k articles) survives interruption.
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/pmcbulk/build.log"; mkdir -p "$SCRATCH/data"
OUT="$SCRATCH/data/pmc_fulltext_bulk.jsonl"; DEST="$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; [ -s "$OUT" ] && aws s3 cp "$OUT" "$DEST" --quiet 2>/dev/null; sleep 120; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; [ -s "$OUT" ] && aws s3 cp "$OUT" "$DEST" --quiet 2>/dev/null' EXIT
pip install -q boto3 2>/dev/null || true
python3 "$HERE/build_pmc_bulk.py" --out "$OUT" --n ${PMC_ARTICLES:-500000} --max-tokens ${PMC_MAXTOK:-8000000000} --workers ${PMC_WORKERS:-64}
aws s3 cp "$OUT" "$DEST" --quiet
echo "PMCBULK_UPLOADED rows=$(wc -l < "$OUT")"
