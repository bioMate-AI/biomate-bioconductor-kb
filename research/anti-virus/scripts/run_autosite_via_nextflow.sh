#!/usr/bin/env bash
# Run BioMate "Run Autosite" (workflow DB id 10787) via the checked-in Nextflow module.
# Requires: Nextflow, Docker, and a linux/amd64-capable runtime (x86_64 host or working QEMU/binfmt).
#
# Usage:
#   ./run_autosite_via_nextflow.sh /abs/path/to/receptor.pdb [/abs/path/to/results_parent]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PDB="${1:?usage: $0 /path/to/receptor.pdb [results_parent]}"
OUT_PARENT="${2:-$ROOT/research/anti-virus/runs/autosite_nf}"
MODULE="$ROOT/backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/run_autosite"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUTDIR="$OUT_PARENT/${STAMP}_autosite_nf"
mkdir -p "$OUTDIR"

cd "$MODULE"
exec nextflow run . -profile docker \
  --pdb_file "$PDB" \
  --output_dir ./autosite_work \
  --outdir "$OUTDIR"
