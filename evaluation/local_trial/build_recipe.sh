#!/bin/bash
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/recipe/build.log"; mkdir -p "$SCRATCH/data"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
aws s3 cp "$S3/midtrain_corpus/db_catalog_corpus.jsonl" "$SCRATCH/data/dbcat.jsonl" --quiet
# full-text source: prefer the growing bulk, else the v1small full-text
aws s3 cp "$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl" "$SCRATCH/data/ft.jsonl" --quiet 2>/dev/null || \
  aws s3 cp "$S3/midtrain_corpus/pmc_fulltext_corpus_v1small.jsonl" "$SCRATCH/data/ft.jsonl" --quiet
echo "full-text rows: $(wc -l < "$SCRATCH/data/ft.jsonl")"
python3 "$HERE/build_recipe_extractor.py" --lit "$SCRATCH/data/ft.jsonl" --dbcat "$SCRATCH/data/dbcat.jsonl" \
  --out "$SCRATCH/data/recipe_sft.jsonl" --gap-out "$SCRATCH/data/tool_coverage_gap.jsonl" --n ${RECIPE_N:-4000}
aws s3 cp "$SCRATCH/data/recipe_sft.jsonl" "$S3/sft/recipe_sft.jsonl" --quiet
aws s3 cp "$SCRATCH/data/tool_coverage_gap.jsonl" "$S3/sft/tool_coverage_gap.jsonl" --quiet
echo "RECIPE_UPLOADED rows=$(wc -l < "$SCRATCH/data/recipe_sft.jsonl")"
