#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/pmcbulk/build.log"
mkdir -p "$SCRATCH/data/txt"; cd "$SCRATCH/data"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
BASE=https://ftp.ncbi.nlm.nih.gov/pub/pmc
# master index of every OA article -> per-article package path (col1). -L follows redirects.
curl -sL --max-time 180 "$BASE/oa_file_list.csv" -o oa_list.csv
echo "oa_file_list.csv bytes: $(wc -c < oa_list.csv)"; echo "header:"; head -1 oa_list.csv
# sample N package paths across the whole corpus (shuf = all eras), strip quotes
tail -n +2 oa_list.csv | awk -F',' '{gsub(/"/,"",$1); print $1}' | shuf | head -${PMC_PKGS:-4000} > pkgs.txt
echo "packages to fetch: $(wc -l < pkgs.txt)"; head -2 pkgs.txt
export BASE
cat pkgs.txt | xargs -P 16 -I {} bash -c 'f="{}"; o="$SCRATCH/data/txt/$(basename "$f")"; curl -sL --max-time 120 -o "$o" "$BASE/$f" && tar xzf "$o" -C "$SCRATCH/data/txt" 2>/dev/null; rm -f "$o"'
echo "extracted article dirs: $(find "$SCRATCH/data/txt" -name '*.nxml' -o -name '*.txt' | wc -l)"
python3 "$HERE/build_pmc_bulk.py" --dir "$SCRATCH/data/txt" --out "$SCRATCH/data/pmc_fulltext_bulk.jsonl" --max-tokens ${PMC_MAXTOK:-3000000000}
aws s3 cp "$SCRATCH/data/pmc_fulltext_bulk.jsonl" "$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl" --quiet
echo "PMCBULK_UPLOADED rows=$(wc -l < "$SCRATCH/data/pmc_fulltext_bulk.jsonl")"
