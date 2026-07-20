#!/bin/bash
# EC2 bootstrap for the autoimmune single-cell corpus (Layers 2-3).
# Runs as user-data (root). Installs deps, syncs code from S3, runs acquisition +
# harmonization, uploads the curated corpus + log to S3, then self-terminates.
# Env (set by the launch user-data): CODE_S3, OUT_S3, DISEASES, CAP, REGION
set -uxo pipefail
LOG=/var/log/autoimmune_corpus.log
exec > >(tee -a "$LOG") 2>&1

REGION="${REGION:-us-west-2}"
CODE_S3="${CODE_S3:?set CODE_S3}"     # e.g. s3://knowledge-datasets-.../autoimmune_sc_corpus/code/
OUT_S3="${OUT_S3:?set OUT_S3}"        # e.g. s3://knowledge-datasets-.../autoimmune_sc_corpus/
DISEASES="${DISEASES:-SLE}"
CAP="${CAP:-500000}"
export AWS_DEFAULT_REGION="$REGION"

cleanup(){ aws s3 cp "$LOG" "${OUT_S3}logs/bootstrap.log" 2>/dev/null || true; shutdown -h now; }
trap cleanup EXIT
# hard safety: terminate no matter what after 6h
( sleep 21600; shutdown -h now ) &

echo "=== $(date -u) install deps ==="
dnf -y install python3.11 python3.11-pip git >/dev/null 2>&1 || dnf -y install python3-pip git >/dev/null 2>&1
PY=$(command -v python3.11 || command -v python3)
$PY -m pip install --quiet --upgrade pip
$PY -m pip install --quiet cellxgene-census scanpy anndata boto3 pyyaml GEOparse

echo "=== fetch code from $CODE_S3 ==="
mkdir -p /opt/ac && aws s3 sync "$CODE_S3" /opt/ac/ && cd /opt/ac

echo "=== Layer 2 acquisition (diseases=$DISEASES cap=$CAP) ==="
$PY collect_expression.py --diseases "$DISEASES" --cap "$CAP" --out data/raw || echo "acquisition returned $?"

echo "=== Layer 3 harmonize ==="
$PY harmonize.py --raw data/raw --out data/curated || echo "harmonize returned $?"

echo "=== upload outputs to $OUT_S3 ==="
aws s3 sync data/curated "${OUT_S3}curated/" || true
aws s3 sync data/raw "${OUT_S3}raw/" --exclude "*" --include "*.h5ad" || true
echo "=== $(date -u) DONE; terminating via EXIT trap ==="
