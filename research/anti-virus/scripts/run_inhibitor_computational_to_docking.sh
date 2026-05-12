#!/usr/bin/env bash
# Full computational inhibitor stack on AWS Batch (steps 1–4): pocket → pharmacophore
# → ADMET → AutoDock Vina. Same API + Batch + S3 as BioMate defaults; requires backend
# on BIOMATE_API_URL (default http://127.0.0.1:8081) and GALAXY_API_KEY or galaxy.yml key.
#
# Demo S3 inputs are the campaign pipeline_demo actives/library (small); override with env
# vars if you use your own screening set.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${BIOMATE_API_URL:=http://127.0.0.1:8081}"
: "${PDB_S3:=s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb}"
: "${REFERENCE_ACTIVES_S3:=s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi}"
: "${COMPOUND_LIBRARY_S3:=s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi}"
: "${SMILES_JSON:=[\"CCO\",\"CC(=O)O\",\"CC(=O)Oc1ccccc1C(=O)O\"]}"
: "${STEP_TIMEOUT:=7200}"

exec python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --api-url "${BIOMATE_API_URL}" \
  --pdb-input "${PDB_S3}" \
  --through-step 4 \
  --reference-actives-s3 "${REFERENCE_ACTIVES_S3}" \
  --compound-library-s3 "${COMPOUND_LIBRARY_S3}" \
  --smiles-json "${SMILES_JSON}" \
  --use-top-pocket-box \
  --step-timeout "${STEP_TIMEOUT}" \
  "$@"
