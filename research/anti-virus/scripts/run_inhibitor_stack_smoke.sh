#!/usr/bin/env bash
# Inhibitor-track smoke: pocket-only Nextflow via BioMate API (same as full pipeline step 1).
# Prerequisites: backend up (default http://127.0.0.1:8081), GALAXY_API_KEY or
#   bootstrap_admin_api_key in backend/config/galaxy.yml, AWS creds for Batch + S3 I/O.
#
# Usage:
#   ./research/anti-virus/scripts/run_inhibitor_stack_smoke.sh
#   PDB_S3=s3://bucket/path/receptor.pdb ./research/anti-virus/scripts/run_inhibitor_stack_smoke.sh --step-timeout 7200
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

: "${BIOMATE_API_URL:=http://127.0.0.1:8081}"
: "${PDB_S3:=s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb}"

exec python3 research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py \
  --api-url "${BIOMATE_API_URL}" \
  --pdb-input "${PDB_S3}" \
  --through-step 1 \
  "$@"
