#!/bin/bash
# Box entry: generate task-aware (instruction) mid-train data for v2 from the full corpora.
set -uo pipefail; SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912; LOGDST="$S3/spot_logs/instmid/build.log"; mkdir -p "$SCRATCH/data"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
aws s3 cp "$S3/midtrain_corpus/kg_corpus.jsonl" "$SCRATCH/data/kg.jsonl" --quiet
aws s3 cp "$S3/midtrain_corpus/db_catalog_corpus.jsonl" "$SCRATCH/data/dbcat.jsonl" --quiet
# literature source for findings/interpretation tasks: PREFER full-text (real Results/Discussion sections),
# top up with a streamed abstract sample. head closes the pipe early so we don't pull the 40GB file.
aws s3 cp "$S3/midtrain_corpus/pmc_fulltext_corpus_v1small.jsonl" "$SCRATCH/data/lit.jsonl" --quiet 2>/dev/null || true
aws s3 cp "$S3/midtrain_corpus/literature_corpus.jsonl" - 2>/dev/null | head -200000 >> "$SCRATCH/data/lit.jsonl" || true
echo "lit source rows (full-text + abstract sample): $(wc -l < "$SCRATCH/data/lit.jsonl")"
python3 "$HERE/build_instruction_midtrain.py" --kg "$SCRATCH/data/kg.jsonl" --dbcat "$SCRATCH/data/dbcat.jsonl" \
  --lit "$SCRATCH/data/lit.jsonl" --out "$SCRATCH/data/instruction_midtrain.jsonl" \
  --kg-n ${KG_N:-250000} --tooldoc-n ${TOOLDOC_N:-60000} --lit-n ${LIT_N:-40000}
aws s3 cp "$SCRATCH/data/instruction_midtrain.jsonl" "$S3/midtrain_corpus/instruction_midtrain.jsonl" --quiet
echo "INSTMID_UPLOADED rows=$(wc -l < "$SCRATCH/data/instruction_midtrain.jsonl")"
