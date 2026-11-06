#!/bin/bash
# Corpus expansion orchestrator — run on the GPU/disk box (bandwidth + disk needed).
# Order: build decontam index -> fetch each source (dedup+decontam inline) -> merge -> upload.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SCRATCH=${SCRATCH:-/opt/dlami/nvme}
COR="$SCRATCH/corpus"; DATA="$SCRATCH/data"; mkdir -p "$COR" "$DATA"
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912/midtrain_corpus
PMC_LICENSE=${PMC_LICENSE:-}          # empty = ALL OA licenses (no topic filter); set to restrict
PMC_LIMIT=${PMC_LIMIT:-200000}

echo "=== [0] decontamination index (vs SFT + holdout) ==="
python3 "$HERE/build_decontam.py" \
  --sft "$DATA/sft_enriched.jsonl" \
  --holdout "$DATA/holdout.jsonl" \
  --out "$DATA/decontam.pkl" || echo "(warn: decontam inputs missing; fetchers will skip decontam)"
DEC="$DATA/decontam.pkl"; [ -f "$DEC" ] || DEC=""

echo "=== [1] PMC (all topics, license-filter only) ==="
python3 "$HERE/fetch_pmc.py" --out "$COR/pmc.jsonl" --limit "$PMC_LIMIT" \
  --license-allow "$PMC_LICENSE" ${DEC:+--decontam "$DEC"} || true

echo "=== [2] Bioconductor vignettes + man pages ==="
python3 "$HERE/fetch_bioconductor.py" --out "$COR/bioc.jsonl" ${DEC:+--decontam "$DEC"} || true

echo "=== [3] multi-engine workflow code (Dockstore TRS) ==="
python3 "$HERE/fetch_workflows.py" --out "$COR/workflows.jsonl" ${DEC:+--decontam "$DEC"} || true

echo "=== [4] forum Q&A (Biostars + Bioconductor support) ==="
python3 "$HERE/fetch_forums.py" --out "$COR/forums.jsonl" --sites biostars,bioc \
  --max-id "${FORUM_MAX_ID:-100000}" ${DEC:+--decontam "$DEC"} || true

echo "=== [5] vendor docs (curated URL list; ToS-respecting) ==="
if [ -f "$HERE/vendor_docs.tsv" ]; then
  python3 "$HERE/fetch_vendor_docs.py" --urls "$HERE/vendor_docs.tsv" \
    --out "$COR/vendor.jsonl" --sft-out "$COR/vendor_diagfix_sft.jsonl" ${DEC:+--decontam "$DEC"} || true
else
  echo "  (skip: create $HERE/vendor_docs.tsv with curated, ToS-cleared PDF URLs)"
fi

echo "=== [6] merge external shards -> external_corpus.jsonl (cross-source dedup) ==="
python3 "$HERE/merge_external.py" --dir "$COR" --out "$COR/external_corpus.jsonl"

echo "=== [7] upload ==="
aws s3 cp "$COR/external_corpus.jsonl" "$S3/external_corpus.jsonl" --quiet
[ -f "$COR/vendor_diagfix_sft.jsonl" ] && aws s3 cp "$COR/vendor_diagfix_sft.jsonl" \
  "s3://biomate-models-399683337364/biomate-core-local-trial/20260912/sft/vendor_diagfix_sft.jsonl" --quiet || true
echo "CORPUS_EXPAND_DONE"
echo "Next: drop external_corpus.jsonl into midtrain_corpus/ and re-run concat_dedup_corpus.py to refresh midtrain_all."
