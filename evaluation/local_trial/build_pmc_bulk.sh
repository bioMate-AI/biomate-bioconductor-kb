#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/pmcbulk/build.log"
mkdir -p "$SCRATCH/data/tars" "$SCRATCH/data/txt"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
DIR=https://ftp.ncbi.nlm.nih.gov/pub/pmc/oa_bulk/oa_comm/txt/
curl -s --max-time 60 "$DIR" | grep -oE 'oa_comm_txt[^"]*\.tar\.gz' | sort -u > "$SCRATCH/data/tarlist.txt"
echo "tarballs available: $(wc -l < "$SCRATCH/data/tarlist.txt")"; head -3 "$SCRATCH/data/tarlist.txt"
K=${PMC_TARS:-25}
head -$K "$SCRATCH/data/tarlist.txt" | while read f; do
  echo "downloading $f"; curl -s --max-time 600 -o "$SCRATCH/data/tars/$f" "$DIR$f" && tar xzf "$SCRATCH/data/tars/$f" -C "$SCRATCH/data/txt" 2>/dev/null; rm -f "$SCRATCH/data/tars/$f"
done
echo "extracted txt files: $(find "$SCRATCH/data/txt" -name '*.txt' | wc -l)"
python3 "$HERE/build_pmc_bulk.py" --dir "$SCRATCH/data/txt" --out "$SCRATCH/data/pmc_fulltext_bulk.jsonl" --max-tokens ${PMC_MAXTOK:-3000000000}
aws s3 cp "$SCRATCH/data/pmc_fulltext_bulk.jsonl" "$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl" --quiet
echo "PMCBULK_UPLOADED rows=$(wc -l < "$SCRATCH/data/pmc_fulltext_bulk.jsonl")"
