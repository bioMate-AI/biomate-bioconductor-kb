#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/toolz/build.log"; mkdir -p "$SCRATCH"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
python3 "$HERE/build_toolz.py" --out "$SCRATCH/tooldocs_corpus.jsonl"
aws s3 cp "$SCRATCH/tooldocs_corpus.jsonl" "$S3/midtrain_corpus/tooldocs_corpus.jsonl" --quiet
echo "TOOLZ_UPLOADED rows=$(wc -l < "$SCRATCH/tooldocs_corpus.jsonl")"
