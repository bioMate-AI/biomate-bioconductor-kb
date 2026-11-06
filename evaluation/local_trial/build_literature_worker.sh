#!/usr/bin/env bash
# CPU-only, bounded by spot_launch's worker timeout; no external teacher/model calls.
set -euo pipefail
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
OUT="$SCRATCH/literature_identified_20261003"
mkdir -p "$OUT"
aws s3 cp "$S3/midtrain_corpus/pmc_fulltext_bulk.jsonl" - --quiet \
  | python3 pmc_filter.py --min-year 2000 \
  | python3 local_literature.py --build "$OUT/literature.sqlite"
(cd "$OUT" && sha256sum literature.sqlite > SHA256SUMS)
aws s3 cp "$OUT/" "$S3/airgap/literature_identified_20261003/" --recursive --quiet
echo 'LITERATURE_INDEX_UPLOADED (retrieval baseline; requires relevance evaluation)'
