#!/usr/bin/env bash
# Provision the ProstT5 weights for foldseek_structure_search (search-from-sequence).
#
# Downloads the ProstT5 protein language model (Heinzinger et al., "Bilingual
# language model for protein sequence and structure", NAR Genomics and
# Bioinformatics 2024, lqae150; https://huggingface.co/Rostlab/ProstT5) via
# `foldseek databases ProstT5`, then uploads it to S3, where the Batch worker
# stages it read-only for the workflow (params.prostt5_model). ProstT5 predicts
# the Foldseek 3Di structural alphabet DIRECTLY from a protein sequence — no
# folding required — so a query FASTA can be searched against a structure DB
# ~1000x cheaper than predicting a structure (AlphaFold/ESMFold) first.
#
# Weights are ~1-2 GB. Run this ONCE on a machine with foldseek + AWS creds +
# enough disk. Mirrors the pattern of tools/prepare_foldseek_db.sh.
#
# Usage:
#   ./prepare_prostt5_model.sh
set -euo pipefail

S3_BASE="${S3_BASE:-s3://biomate-production-data-399683337364/reference/foldseek}"
S3_DEST="$S3_BASE/prostt5"
WORK="${WORK:-$(mktemp -d)}"

command -v foldseek >/dev/null || { echo "foldseek not on PATH — install the static binary from https://mmseqs.com/foldseek/"; exit 1; }
command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }

echo "[1/3] Downloading ProstT5 weights -> $WORK/prostt5"
mkdir -p "$WORK/tmp"
foldseek databases ProstT5 "$WORK/prostt5" "$WORK/tmp"

echo "[2/3] Uploading weights to $S3_DEST/"
aws s3 cp --recursive "$WORK/prostt5" "$S3_DEST/"

echo "[3/3] Done. On Batch, stage it read-only and set:"
echo "    --query_type sequence --prostt5_model <staged-dir>/prostt5"
echo "S3 location: $S3_DEST/"
echo
echo "Batch staging (in the job, before the workflow):"
echo "    aws s3 cp --recursive $S3_DEST/ /mnt/foldseek/prostt5/ && \\"
echo "    export PROSTT5_MODEL=/mnt/foldseek/prostt5"
