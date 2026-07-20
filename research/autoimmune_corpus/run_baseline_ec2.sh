#!/bin/bash
# EC2 bootstrap: Phase-B baseline gate + SLEDAI extraction. Self-terminating.
# Env (from user-data): CODE_S3, OUT_S3, CORPUS_S3, REGION
set -uxo pipefail
LOG=/var/log/autoimmune_baseline.log
exec > >(tee -a "$LOG") 2>&1
REGION="${REGION:-us-west-2}"; export AWS_DEFAULT_REGION="$REGION"
CODE_S3="${CODE_S3:?}"; OUT_S3="${OUT_S3:?}"
CORPUS_S3="${CORPUS_S3:-${OUT_S3}curated/autoimmune_sc_corpus.h5ad}"

cleanup(){ aws s3 cp "$LOG" "${OUT_S3}logs/baseline.log" 2>/dev/null || true; shutdown -h now; }
trap cleanup EXIT
( sleep 21600; shutdown -h now ) &

echo "=== $(date -u) deps ==="
dnf -y install python3.11 python3.11-pip git >/dev/null 2>&1 || dnf -y install python3-pip git >/dev/null 2>&1
PY=$(command -v python3.11 || command -v python3)
$PY -m pip install --quiet --upgrade pip
$PY -m pip install --quiet scanpy anndata scikit-learn scipy boto3 pyyaml requests

echo "=== fetch code + corpus ==="
mkdir -p /opt/ac && aws s3 sync "$CODE_S3" /opt/ac/ && cd /opt/ac
mkdir -p work out && aws s3 cp "$CORPUS_S3" work/corpus.h5ad

echo "=== Phase-B baseline gate ==="
$PY baseline_gate.py --corpus work/corpus.h5ad --out out || echo "baseline rc=$?"
# NB: SLEDAI extraction (inspect_perez_labels.py) already completed — labels in S3.

echo "=== upload results ==="
aws s3 sync out "${OUT_S3}labels/baseline/" --exclude "*.h5ad" || true
echo "=== $(date -u) DONE ==="
