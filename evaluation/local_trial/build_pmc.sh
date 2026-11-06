#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/pmc/build.log"; mkdir -p "$SCRATCH"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
python3 "$HERE/build_pmc_eutils.py" --out "$SCRATCH/pmc_fulltext_corpus.jsonl" --max-tokens ${PMC_MAXTOK:-3000000000}
aws s3 cp "$SCRATCH/pmc_fulltext_corpus.jsonl" "$S3/midtrain_corpus/pmc_fulltext_corpus.jsonl" --quiet
echo "PMC_UPLOADED rows=$(wc -l < "$SCRATCH/pmc_fulltext_corpus.jsonl")"
