#!/usr/bin/env bash
# Continue inhibitor steps 5–6 using top-pocket PDB (smaller receptor than full 9P3I tetramer).
# See research/anti-virus/docs/ANDV_CAMPAIGN_LESSONS_LEARNED.md §7.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUN="${ROOT}/research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
POCKET="${RUN}/01_pocket/structure_top_pocket.pdb"
S3_REC="s3://biomate-nextflow-work/inputs/andv_campaign/20260514/9P3I_top_pocket_only.pdb"

test -f "$POCKET"
aws s3 cp "$POCKET" "$S3_REC"
cd "$ROOT"
exec python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --api-url "${BIOMATE_API_URL:-http://127.0.0.1:8081}" \
  --append-to-run "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z" \
  --user-id "${BIOMATE_NF_USER_ID:-parallel-inhibitor-20260513T032000Z}" \
  --pdb-input "$S3_REC" \
  --through-step 6 \
  --reference-actives-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/reference_actives.smi \
  --compound-library-s3 s3://biomate-nextflow-work/inputs/andv_campaign/pipeline_demo_20260509/compound_library.smi \
  --ligand-s3 'CC(=O)Oc1ccccc1C(=O)O' \
  --seed-smiles 'CC(=O)Oc1ccccc1C(=O)O' \
  --gromacs-n-steps 25000 \
  --step-timeout 43200 \
  --reinvent-n-steps 80 \
  "$@"
