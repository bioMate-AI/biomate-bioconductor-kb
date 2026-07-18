#!/usr/bin/env bash
# Build an MMseqs2 target database from a FASTA and upload it to S3, where the
# Batch worker stages it read-only for the workflow (params.mmseqs_db). Run ONCE
# on a machine with mmseqs + AWS creds and enough disk (UniRef50 ~a few GB;
# nr / UniRef90 ~tens of GB). MMseqs2 is GPL-3.0 open source — no license fee.
#
# Usage:
#   ./prepare_mmseqs_db.sh uniref50.fasta uniref50      # protein FASTA -> DB
#
# --gpu 1 search needs a GPU-padded DB (makepaddedseqdb); this script builds it
# when available so the workflow can run GPU or CPU against the same S3 prefix.
# Verified end-to-end on 2026-07-18 with a small demo DB (build -> S3 -> stage ->
# search); this is the same pattern at full scale.
set -euo pipefail

FASTA="${1:?usage: prepare_mmseqs_db.sh <sequences.fasta> [dbname]}"
NAME="${2:-targetdb}"
S3_BASE="${S3_BASE:-s3://biomate-production-data-399683337364/reference/mmseqs2}"
WORK="${WORK:-$(mktemp -d)}"

command -v mmseqs >/dev/null || { echo "mmseqs not on PATH (install the static binary from https://mmseqs.com/)"; exit 1; }
command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }

echo "[1/3] createdb: $FASTA -> $WORK/$NAME"
mmseqs createdb "$FASTA" "$WORK/$NAME"

echo "[2/3] GPU-padded DB (for --gpu 1); skipped on older mmseqs"
mmseqs makepaddedseqdb "$WORK/$NAME" "$WORK/${NAME}_gpu" >/dev/null 2>&1 && echo "  built ${NAME}_gpu" || echo "  (makepaddedseqdb unavailable — CPU search only)"

echo "[3/3] Upload to $S3_BASE/$NAME/"
aws s3 cp --recursive "$WORK" "$S3_BASE/$NAME/" --exclude "*" --include "${NAME}*"
echo "Done. On Batch, stage read-only and set:"
echo "    aws s3 cp --recursive $S3_BASE/$NAME/ /mnt/mmseqs/$NAME.d/ && \\"
echo "    --mmseqs_db /mnt/mmseqs/$NAME.d/$NAME   (add --use_gpu true on a GPU node)"
