#!/bin/bash
# EC2 bootstrap: cyclic-peptide dataset (CycPeptMPDB) + permeability baseline gate,
# computed inside the biomni-admet ECR image (rdkit). Host handles S3. Self-terminating.
# Env (user-data): CODE_S3, OUT_S3, IMAGE, REGION
set -uxo pipefail
LOG=/var/log/cycpep.log
exec > >(tee -a "$LOG") 2>&1
REGION="${REGION:-us-west-2}"; export AWS_DEFAULT_REGION="$REGION"
CODE_S3="${CODE_S3:?}"; OUT_S3="${OUT_S3:?}"; IMAGE="${IMAGE:?}"

cleanup(){ aws s3 cp "$LOG" "${OUT_S3}logs/cycpep.log" 2>/dev/null || true; shutdown -h now; }
trap cleanup EXIT
( sleep 14400; shutdown -h now ) &

echo "=== $(date -u) docker ==="
dnf -y install docker >/dev/null 2>&1
systemctl start docker

echo "=== code + data ==="
mkdir -p /opt/ac && aws s3 sync "$CODE_S3" /opt/ac/ && cd /opt/ac
mkdir -p data/cycpep out
curl -sL "http://cycpeptmpdb.com/static//download/peptides/CycPeptMPDB_Peptide_All.csv" \
     -o data/cycpep/CycPeptMPDB_Peptide_All.csv
ls -la data/cycpep/

echo "=== ECR login + pull ==="
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${IMAGE%%/*}"
docker pull "$IMAGE"

echo "=== baseline in container (rdkit) ==="
docker run --rm -v /opt/ac:/work -w /work "$IMAGE" bash -lc \
  "python cycpep_baseline.py --csv data/cycpep/CycPeptMPDB_Peptide_All.csv --out out \
   || python3 cycpep_baseline.py --csv data/cycpep/CycPeptMPDB_Peptide_All.csv --out out" \
  || echo "container rc=$?"

echo "=== upload ==="
aws s3 cp data/cycpep/CycPeptMPDB_Peptide_All.csv "${OUT_S3}raw/CycPeptMPDB_Peptide_All.csv" || true
aws s3 sync out "${OUT_S3}baseline/" || true
echo "=== $(date -u) DONE ==="
