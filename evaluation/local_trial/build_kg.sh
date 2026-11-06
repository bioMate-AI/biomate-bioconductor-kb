#!/bin/bash
# Box entry: download FULL PrimeKG (Dataverse) + MAP-KG (HF), verbalize to text, upload to S3.
set -uo pipefail
SCRATCH=${SCRATCH:-/opt/dlami/nvme}; HERE=$(cd "$(dirname "$0")" && pwd)
S3=s3://biomate-models-399683337364/biomate-core-local-trial/20260912
LOGDST="$S3/spot_logs/kg/build.log"; mkdir -p "$SCRATCH/kg"; cd "$SCRATCH/kg"
( while true; do aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null; sleep 30; done ) &
trap 'aws s3 cp /var/log/ud.log "$LOGDST" --quiet 2>/dev/null' EXIT
echo "[kg] downloading PrimeKG kg.csv (936MB) + MAP-KG CSVs"
curl -sSL --retry 3 -o kg.csv "https://dataverse.harvard.edu/api/access/datafile/6180620"
curl -sSL --retry 3 -o gg.csv "https://huggingface.co/datasets/RainGate/MAP-KG/resolve/main/GENE-GENE_filtered_by_existing_genes.csv"
curl -sSL --retry 3 -o dg.csv "https://huggingface.co/datasets/RainGate/MAP-KG/resolve/main/DRUG-GENE_filtered_by_existing_drugs_and_genes.csv"
ls -lah kg.csv gg.csv dg.csv 2>&1
python3 "$HERE/build_kg_corpus.py" --primekg kg.csv --mapkg-gg gg.csv --mapkg-dg dg.csv --out kg_corpus.jsonl
aws s3 cp kg_corpus.jsonl "$S3/midtrain_corpus/kg_corpus.jsonl" --quiet
echo "KG_UPLOADED rows=$(wc -l < kg_corpus.jsonl) bytes=$(stat -c%s kg_corpus.jsonl 2>/dev/null || stat -f%z kg_corpus.jsonl)"
