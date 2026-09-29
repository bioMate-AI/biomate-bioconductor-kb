#!/bin/bash
# PMC full-text via AWS Open Data (s3://pmc-oa-opendata) — box-native, no NCBI FTP (which returns a 990B stub).
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/pmcbulk/build.log"
BUCKET=s3://pmc-oa-opendata; mkdir -p "$SCRATCH/data/txt"; cd "$SCRATCH/data"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
N=${PMC_ARTICLES:-8000}
# list N per-article prefixes (PMC<id>.<ver>/), head closes the paginated listing early
aws s3 ls --no-sign-request "$BUCKET/" 2>/dev/null | head -$N | awk '{print $2}' | sed 's#/$##' > prefixes.txt
echo "article prefixes: $(wc -l < prefixes.txt)"; head -2 prefixes.txt
export BUCKET SCRATCH
# download each article's plain-text .txt in parallel
cat prefixes.txt | xargs -P 32 -I {} bash -c 'aws s3 cp --no-sign-request "$BUCKET/{}/{}.txt" "$SCRATCH/data/txt/{}.txt" --quiet 2>/dev/null || true'
echo "downloaded txt files: $(find "$SCRATCH/data/txt" -name '*.txt' | wc -l)"
python3 "$HERE/build_pmc_bulk.py" --dir "$SCRATCH/data/txt" --out "$SCRATCH/data/pmc_fulltext_bulk.jsonl" --max-tokens ${PMC_MAXTOK:-3000000000}
aws s3 cp "$SCRATCH/data/pmc_fulltext_bulk.jsonl" "$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl" --quiet
echo "PMCBULK_UPLOADED rows=$(wc -l < "$SCRATCH/data/pmc_fulltext_bulk.jsonl")"
