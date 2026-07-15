#!/usr/bin/env bash
# Provision the Foldseek target index for foldseek_structure_search.
#
# Downloads a PREBUILT Foldseek structure database (hosted by the Steinegger lab)
# and uploads it to S3, where the Batch worker stages it read-only for the
# workflow (params.foldseek_db). Run this ONCE on a machine with foldseek + AWS
# creds + enough disk (Swiss-Prot ~a few GB; full AlphaFold/UniProt ~hundreds of GB).
#
# Usage:
#   ./prepare_foldseek_db.sh                       # default: Alphafold/Swiss-Prot (small)
#   DB=Alphafold/UniProt ./prepare_foldseek_db.sh  # full AFDB (large — hundreds of GB)
#   DB=PDB ./prepare_foldseek_db.sh                # PDB
#
# Verified end-to-end on 2026-07-15 with a small demo DB (build -> S3 -> stage ->
# search); this script is the same pattern at full scale.
set -euo pipefail

DB="${DB:-Alphafold/Swiss-Prot}"
NAME="$(echo "$DB" | tr '/' '-' | tr '[:upper:]' '[:lower:]')"   # e.g. alphafold-swiss-prot
S3_BASE="${S3_BASE:-s3://biomate-production-data-399683337364/reference/foldseek}"
S3_DEST="$S3_BASE/$NAME"
WORK="${WORK:-$(mktemp -d)}"

command -v foldseek >/dev/null || { echo "foldseek not on PATH — install the static binary from https://mmseqs.com/foldseek/"; exit 1; }
command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }

echo "[1/3] Downloading prebuilt Foldseek DB: $DB -> $WORK/$NAME"
mkdir -p "$WORK/tmp"
foldseek databases "$DB" "$WORK/$NAME" "$WORK/tmp"

echo "[2/3] Uploading index to $S3_DEST/"
aws s3 cp --recursive "$WORK" "$S3_DEST/" --exclude "*" --include "${NAME}*"

echo "[3/3] Done. On Batch, stage it read-only and set:"
echo "    --foldseek_db <staged-dir>/$NAME"
echo "S3 location: $S3_DEST/"
echo
echo "Batch staging (in the job, before the workflow):"
echo "    aws s3 cp --recursive $S3_DEST/ /mnt/foldseek/$NAME.d/ && \\"
echo "    export FOLDSEEK_DB=/mnt/foldseek/$NAME.d/$NAME"
