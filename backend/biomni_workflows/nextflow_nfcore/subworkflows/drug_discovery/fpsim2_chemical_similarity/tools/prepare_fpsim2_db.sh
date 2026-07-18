#!/usr/bin/env bash
# Build an FPSim2 fingerprint database and upload it to S3, where the Batch
# worker stages it read-only for the workflow (params.fpsim2_db). Run ONCE on a
# machine with FPSim2 + RDKit + AWS creds and enough RAM (whole-ChEMBL ~2.4M is
# routine; PubChem ~100M is large).
#
# Usage:
#   ./prepare_fpsim2_db.sh molecules.smi                 # .smi: "SMILES id" per line
#   ./prepare_fpsim2_db.sh chembl_35.sdf chembl35        # .sdf source, custom name
#
# ChEMBL: export SMILES+molregno from the ChEMBL SQLite to a .smi, then run this.
# Verified end-to-end on 2026-07-18 with a small demo DB (build -> S3 -> stage ->
# search); this script is the same pattern at full scale.
set -euo pipefail

SRC="${1:?usage: prepare_fpsim2_db.sh <molecules.smi|.sdf> [dbname]}"
NAME="${2:-chembl}"
S3_BASE="${S3_BASE:-s3://biomate-production-data-399683337364/reference/fpsim2}"
WORK="${WORK:-$(mktemp -d)}"
DB="$WORK/${NAME}.h5"

command -v aws >/dev/null || { echo "aws CLI not found"; exit 1; }
python3 -c "import FPSim2, rdkit" 2>/dev/null || { echo "FPSim2 + RDKit not installed (pip install FPSim2 rdkit)"; exit 1; }

echo "[1/2] Building FPSim2 DB ($NAME) from $SRC -> $DB"
python3 - "$SRC" "$DB" <<'PY'
import sys
from FPSim2.io import create_db_file
# mol_format=None auto-detects from the file extension (.smi / .sdf).
create_db_file(sys.argv[1], sys.argv[2], mol_format=None,
               fp_type="Morgan", fp_params={"radius": 2, "fpSize": 2048})
print("built", sys.argv[2])
PY

echo "[2/2] Uploading to $S3_BASE/${NAME}.h5"
aws s3 cp "$DB" "$S3_BASE/${NAME}.h5"
echo "Done. On Batch, stage read-only and set:"
echo "    aws s3 cp $S3_BASE/${NAME}.h5 /mnt/fpsim2/${NAME}.h5 && \\"
echo "    --fpsim2_db /mnt/fpsim2/${NAME}.h5"
