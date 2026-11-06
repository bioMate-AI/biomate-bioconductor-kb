#!/bin/bash
# Build the DB catalog corpus from the FULL enriched DB on S3 (local is a stub) -> upload.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
DBSRC="s3://biomate-models-399683337364/biomate-core-local-trial/20260912/knowledge/snapshots/20260912T172822Z-df49deae4284415084230452b19e1af9/files/galaxy_ai_tools.db"
LOGDST="$S3/spot_logs/dbcorpus/build.log"; mkdir -p "$SCRATCH/d"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
aws s3 cp "$DBSRC" "$SCRATCH/d/full.db" --quiet
python3 "$HERE/build_db_corpus.py" --db "$SCRATCH/d/full.db" --out "$SCRATCH/d/db_catalog_corpus.jsonl" --repeat "${DB_REPEAT:-3}"
aws s3 cp "$SCRATCH/d/db_catalog_corpus.jsonl" "$S3/midtrain_corpus/db_catalog_corpus.jsonl" --quiet
echo "DBCORPUS_UPLOADED rows=$(wc -l < "$SCRATCH/d/db_catalog_corpus.jsonl")"
