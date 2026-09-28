#!/bin/bash
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/forum/build.log"; mkdir -p "$SCRATCH/f"; cd "$SCRATCH/f"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
pip3 install -q py7zr 2>&1 | tail -1 || pip install -q py7zr 2>&1 | tail -1
python3 "$HERE/build_forum_corpus.py" --out forum_corpus.jsonl --sources "${FORUM_SRC:-se,galaxy,reddit,bioc}"
aws s3 cp forum_corpus.jsonl "$S3/midtrain_corpus/forum_corpus.jsonl" --quiet
echo "FORUM_UPLOADED rows=$(wc -l < forum_corpus.jsonl)"
