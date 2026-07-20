#!/bin/bash
# Download Replogle 2022 Perturb-seq (BioProject PRJNA831566 / GEO GSE204343)
# to s3://knowledge-datasets-1759951976/replogle_2022/
#
# Run on EC2:  nohup bash download_replogle_2022.sh > /tmp/replogle_dl.log 2>&1 &
#
# Key files (Replogle et al. 2022, Nature 2022):
#   - K562 genome-wide Perturb-seq: essential gene subset (~660 genes)
#   - RPE1 genome-wide Perturb-seq
#   - GEO h5 files: GSM617xxxx
#   Total size: ~25-50 GB

set -euo pipefail

BUCKET="s3://knowledge-datasets-1759951976/replogle_2022"
TMPDIR="/tmp/replogle_staging"
mkdir -p "$TMPDIR"

echo "[$(date -u +%FT%TZ)] Starting Replogle 2022 download"

# --- Option 1: Download via datasets Python package (preferred) ---
python3 - <<'PYEOF'
import subprocess, sys, os

# The Replogle 2022 data is deposited on Figshare + GEO
# Primary source: GEO GSE204343 supplementary files
# Also mirrored on Figshare at: https://doi.org/10.25452/figshare.plus.19312739

BUCKET = "s3://knowledge-datasets-1759951976/replogle_2022"
TMPDIR = "/tmp/replogle_staging"

# Direct download URLs from GEO supplementary files
# GSE204343 - Replogle 2022 "Mapping information-rich genotype-phenotype landscapes"
files = {
    "GSE204343_K562_essential_raw_singlecell_01.h5ad.gz":
        "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE204nnn/GSE204343/suppl/GSE204343_K562_essential_raw_singlecell_01.h5ad.gz",
    "GSE204343_K562_gwps_raw_singlecell_01.h5ad.gz":
        "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE204nnn/GSE204343/suppl/GSE204343_K562_gwps_raw_singlecell_01.h5ad.gz",
    "GSE204343_rpe1_raw_singlecell_01.h5ad.gz":
        "https://ftp.ncbi.nlm.nih.gov/geo/series/GSE204nnn/GSE204343/suppl/GSE204343_rpe1_raw_singlecell_01.h5ad.gz",
}

import urllib.request, os, subprocess

for fname, url in files.items():
    local = os.path.join(TMPDIR, fname)
    s3_key = f"{BUCKET}/{fname}"

    # Check S3 first
    result = subprocess.run(["aws", "s3", "ls", s3_key], capture_output=True)
    if result.returncode == 0:
        print(f"EXISTS: {fname}")
        continue

    print(f"Downloading {fname} ...")
    try:
        urllib.request.urlretrieve(url, local)
        subprocess.run(["aws", "s3", "cp", local, s3_key,
                        "--storage-class", "INTELLIGENT_TIERING"], check=True)
        os.unlink(local)
        print(f"OK: {fname}")
    except Exception as e:
        print(f"FAIL {fname}: {e}")
        if os.path.exists(local):
            os.unlink(local)
PYEOF

echo "[$(date -u +%FT%TZ)] Replogle 2022 download complete"
echo "Files at: $BUCKET"
aws s3 ls "$BUCKET/" --recursive --human-readable --summarize 2>/dev/null | tail -5
