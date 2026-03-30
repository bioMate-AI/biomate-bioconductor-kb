#!/usr/bin/env bash
# build_alphafold_db.sh -- one-time job to build Foldseek + MMseqs2 indexes
# from the AlphaFold Human Proteome and upload to S3.
#
# Source: EBI FTP -- direct HTTP download, no GCS/gsutil needed
#   https://ftp.ebi.ac.uk/pub/databases/alphafold/latest/UP000005640_9606_HUMAN_v6.tar
#   ~4.8 GB compressed tarball, ~48k mmCIF structures
#
# Instance sizing:
#   Minimum:     t3.xlarge  (16 GB RAM, 4 vCPU,  ~$0.17/hr; spot ~$0.05/hr)
#   Recommended: t3.2xlarge (32 GB RAM, 8 vCPU,  ~$0.33/hr; spot ~$0.10/hr)
#
#   Launch with 40 GB gp3 root volume: 5 GB tarball + 10 GB extracted + 15 GB DB
#   Total cost: ~$0.05-0.10 for the full build on spot (~1 hour runtime)
#
# Prerequisites (install with conda):
#   conda install -c bioconda foldseek mmseqs2 -y
#   # AWS CLI pre-installed on Amazon Linux 2023 AMIs
#
# Usage:
#   bash build_alphafold_db.sh

set -euo pipefail

S3_BASE="s3://biomate-structure-db/alphafold/human"
EBI_URL="https://ftp.ebi.ac.uk/pub/databases/alphafold/latest/UP000005640_9606_HUMAN_v6.tar"
WORK_DIR="${TMPDIR:-/tmp}/af_db_build"
NCPUS=$(nproc)

echo "=== AlphaFold DB build ==="
echo "  S3 target : ${S3_BASE}"
echo "  Source    : ${EBI_URL}"
echo "  Work dir  : ${WORK_DIR}"
echo "  CPUs      : ${NCPUS}"
echo ""

mkdir -p "${WORK_DIR}/mmcif_files" "${WORK_DIR}/fasta" \
         "${WORK_DIR}/foldseek_db" "${WORK_DIR}/mmseqs2_db"
cd "${WORK_DIR}"

# ---------------------------------------------------------------------------
# Step 1: Download human proteome tarball from EBI FTP
# ---------------------------------------------------------------------------
echo "[1/5] Downloading UP000005640_9606_HUMAN_v6.tar from EBI (~4.8 GB)..."

wget -c --progress=dot:giga \
    "${EBI_URL}" \
    -O human_proteome.tar

echo "  Downloaded: $(du -sh human_proteome.tar | cut -f1)"
echo "  Extracting mmCIF files..."

tar -xf human_proteome.tar -C mmcif_files/ --wildcards '*.cif' 2>/dev/null \
    || tar -xf human_proteome.tar -C mmcif_files/

N_CIF=$(ls mmcif_files/*.cif 2>/dev/null | wc -l)
echo "  ${N_CIF} mmCIF files extracted"

# ---------------------------------------------------------------------------
# Step 2: Extract FASTA sequences from mmCIF for MMseqs2
# ---------------------------------------------------------------------------
echo "[2/5] Extracting FASTA sequences..."

python3 - << 'PYEOF'
import re
from pathlib import Path

cif_dir  = Path("mmcif_files")
fasta_out = open("fasta/human_proteome.fasta", "w")
written = 0

for cif in sorted(cif_dir.glob("*.cif")):
    m = re.match(r"AF-([A-Z0-9]+)-", cif.stem)
    protein_id = m.group(1) if m else cif.stem

    # Try _entity_poly.pdbx_seq_one_letter_code_can first, then plain version
    text = cif.read_text(errors="replace")
    for pattern in [
        r"_entity_poly\.pdbx_seq_one_letter_code_can\s+([A-Za-z\n;]+)",
        r"_entity_poly\.pdbx_seq_one_letter_code\s+([A-Za-z\n;]+)",
    ]:
        seq_match = re.search(pattern, text)
        if seq_match:
            seq = seq_match.group(1).strip().strip(";").replace("\n", "")
            if seq:
                fasta_out.write(f">{protein_id}\n{seq}\n")
                written += 1
                break

fasta_out.close()
print(f"  FASTA: {written} sequences written")
PYEOF

# ---------------------------------------------------------------------------
# Step 3: Build Foldseek structural database
# ---------------------------------------------------------------------------
echo "[3/5] Building Foldseek structural database..."

foldseek createdb mmcif_files/ foldseek_db/af_db \
    --threads "${NCPUS}"

foldseek createindex foldseek_db/af_db /tmp/foldseek_tmp \
    --threads "${NCPUS}"

echo "  Foldseek DB size: $(du -sh foldseek_db/ | cut -f1)"

# ---------------------------------------------------------------------------
# Step 4: Build MMseqs2 sequence database
# ---------------------------------------------------------------------------
echo "[4/5] Building MMseqs2 sequence database..."

mmseqs createdb fasta/human_proteome.fasta mmseqs2_db/af_db \
    --threads "${NCPUS}"

mmseqs createindex mmseqs2_db/af_db /tmp/mmseqs2_tmp \
    --threads "${NCPUS}"

echo "  MMseqs2 DB size: $(du -sh mmseqs2_db/ | cut -f1)"

# ---------------------------------------------------------------------------
# Step 5: Upload to S3
# ---------------------------------------------------------------------------
echo "[5/5] Uploading to S3..."

aws s3 sync foldseek_db/ "${S3_BASE}/foldseek_db/" \
    --storage-class STANDARD_IA \
    --no-progress

aws s3 sync mmseqs2_db/ "${S3_BASE}/mmseqs2_db/" \
    --storage-class STANDARD_IA \
    --no-progress

aws s3 cp fasta/human_proteome.fasta "${S3_BASE}/fasta/human_proteome.fasta" \
    --storage-class STANDARD_IA

# Write manifest
python3 - << 'PYEOF'
import json, datetime
from pathlib import Path

ncif = len(list(Path("mmcif_files").glob("*.cif")))
manifest = {
    "built_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "source": "https://ftp.ebi.ac.uk/pub/databases/alphafold/latest/UP000005640_9606_HUMAN_v6.tar",
    "organism": "Homo sapiens (human proteome)",
    "alphafold_version": "v6",
    "num_structures": ncif,
    "foldseek_db":  "s3://biomate-structure-db/alphafold/human/foldseek_db/",
    "mmseqs2_db":   "s3://biomate-structure-db/alphafold/human/mmseqs2_db/",
    "fasta":        "s3://biomate-structure-db/alphafold/human/fasta/human_proteome.fasta",
}
with open("manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)
print(json.dumps(manifest, indent=2))
PYEOF

aws s3 cp manifest.json "${S3_BASE}/manifest.json"

echo ""
echo "=== Build complete ==="
echo "  Foldseek DB : ${S3_BASE}/foldseek_db/"
echo "  MMseqs2 DB  : ${S3_BASE}/mmseqs2_db/"
echo "  Manifest    : ${S3_BASE}/manifest.json"
echo ""
echo "  To verify: aws s3 ls ${S3_BASE}/foldseek_db/"
