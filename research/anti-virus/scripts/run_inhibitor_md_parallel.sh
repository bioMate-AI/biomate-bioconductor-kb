#!/usr/bin/env bash
# Launch GROMACS MD (step 5) for multiple ZINC150 hits + aspirin control in parallel.
# Requires BioMate backend at BIOMATE_API_URL (default http://127.0.0.1:8081).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
TRACK="$ROOT/research/anti-virus/science_sprint/track_inh_md.py"
BASE_RUN="${BASE_RUN:-research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z}"
API_URL="${BIOMATE_API_URL:-http://127.0.0.1:8081}"
N_STEPS="${GROMACS_N_STEPS:-500000}"
LOG_DIR="${LOG_DIR:-/tmp/inhibitor_md_parallel_$(date +%s)}"
mkdir -p "$LOG_DIR"

declare -A LIGANDS=(
  [inh02]="CNC1=NC(N)=C2NCCN=C2N1"
  [inh03]="Nc1oc2c(N)[n+]([O-])n(O)c2c1O"
  [inh04]="O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@@H]1O"
  [inh05]="C[C@]12NCCN3CCN(CCN1)[C@@H]32"
  [aspirin]="CC(=O)Oc1ccccc1C(=O)O"
)

echo "Logs -> $LOG_DIR"
echo "MD steps=$N_STEPS api=$API_URL"

for suffix in "${!LIGANDS[@]}"; do
  smiles="${LIGANDS[$suffix]}"
  log="$LOG_DIR/${suffix}.log"
  echo "Starting $suffix ..."
  (
    cd "$ROOT"
    python3 "$TRACK" \
      --base-run "$BASE_RUN" \
      --api-url "$API_URL" \
      --ligand-smiles "$smiles" \
      --step-suffix "$suffix" \
      --gromacs-n-steps "$N_STEPS" \
      --no-gromacs-gpu \
      ${FORCE_RERUN:+--force-rerun}
  ) >"$log" 2>&1 &
  echo "$suffix pid=$! log=$log"
done

echo "All jobs launched. Tail: tail -f $LOG_DIR/*.log"
