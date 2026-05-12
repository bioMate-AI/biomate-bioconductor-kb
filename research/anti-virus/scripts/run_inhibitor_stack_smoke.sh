#!/usr/bin/env bash
# Inhibitor-track quick check: pocket-only (step 1). For the full computational stack through
# Vina (steps 1–4 on AWS Batch), use run_inhibitor_computational_to_docking.sh instead.
#
# Prerequisites: BioMate Nextflow API reachable (default http://127.0.0.1:8081 — this is the
# HTTP service that submits Batch jobs; AWS CLI/credentials are separate and used by Batch).
# Auth: GALAXY_API_KEY or bootstrap_admin_api_key in backend/config/galaxy.yml.
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
