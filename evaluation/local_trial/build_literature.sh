#!/bin/bash
# Box entry: build the biomedical literature corpus (recent PubMed baseline, relevance-filtered) and
# upload to S3. stdlib-only parser -> no pip/torch needed (noop bootstrap).
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/literature/build.log"
mkdir -p "$SCRATCH"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
OUT="$SCRATCH/literature_corpus.jsonl"
NCPU=$(nproc 2>/dev/null || echo 8); [ "$NCPU" -gt 12 ] && NCPU=12   # cap parallel FTP pulls to avoid NCBI throttle
# ENTIRE PubMed baseline, ALL topics (no relevance filter). start=1 files=1400 covers all ~1334 files.
python3 "$HERE/build_literature_corpus.py" --out "$OUT" \
  --start "${LIT_START:-1}" --files "${LIT_FILES:-1400}" --workers "${LIT_WORKERS:-$NCPU}"
aws s3 cp "$OUT" "$S3/midtrain_corpus/literature_corpus.jsonl" --quiet
echo "LITERATURE_UPLOADED rows=$(wc -l < "$OUT") bytes=$(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT")"
