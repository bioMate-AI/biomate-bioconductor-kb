#!/usr/bin/env bash
# test_protein_dynamics.sh
#
# Smoke-test for the Protein Dynamics Conformational Ensemble pipeline.
# Uses ubiquitin (1UBQ) as input — a well-characterised, small (76 aa) protein.
#
# Usage:
#   # Local (Docker required):
#   bash test_data/test_protein_dynamics.sh
#
#   # AWS Batch:
#   PROFILE=aws bash test_data/test_protein_dynamics.sh
#
# Environment variables (all optional):
#   PROFILE        — nextflow profile to use (default: local)
#   N_SAMPLES      — number of conformations to generate (default: 20)
#   OUTDIR         — output directory or S3 prefix
#                    (default: s3://biomate-nextflow-work/test-outputs/protein-dynamics/)
#   NXF_WORK       — Nextflow work directory (default: /tmp/nxf-protein-dynamics-work)

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PROFILE="${PROFILE:-local}"
N_SAMPLES="${N_SAMPLES:-20}"
OUTDIR="${OUTDIR:-s3://biomate-nextflow-work/test-outputs/protein-dynamics/}"
NXF_WORK="${NXF_WORK:-/tmp/nxf-protein-dynamics-work}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PDB_FILE="${SCRIPT_DIR}/1UBQ.pdb"

echo "======================================================================"
echo "  Protein Dynamics Conformational Ensemble — Smoke Test"
echo "======================================================================"
echo "  Profile   : ${PROFILE}"
echo "  n_samples : ${N_SAMPLES}"
echo "  outdir    : ${OUTDIR}"
echo "  work dir  : ${NXF_WORK}"
echo "======================================================================"

# ── Download 1UBQ (ubiquitin) if not already present ─────────────────────────
if [[ ! -f "${PDB_FILE}" ]]; then
    echo "[1/4] Downloading 1UBQ.pdb from RCSB…"
    curl -fsSL "https://files.rcsb.org/download/1UBQ.pdb" -o "${PDB_FILE}"
    echo "      Saved to ${PDB_FILE}"
else
    echo "[1/4] Using cached ${PDB_FILE}"
fi

# Quick sanity check: file must contain ATOM records
if ! grep -q "^ATOM" "${PDB_FILE}"; then
    echo "ERROR: ${PDB_FILE} does not look like a valid PDB (no ATOM records)." >&2
    exit 1
fi
RESIDUE_COUNT=$(grep -c "^ATOM" "${PDB_FILE}" || true)
echo "      Structure has ${RESIDUE_COUNT} ATOM lines (1UBQ: 76 residues × ~6–8 atoms = ~534 expected)"

# ── Check nextflow is available ───────────────────────────────────────────────
echo "[2/4] Checking Nextflow installation…"
if ! command -v nextflow &>/dev/null; then
    echo "ERROR: 'nextflow' not found in PATH." >&2
    echo "       Install with: curl -s https://get.nextflow.io | bash" >&2
    exit 1
fi
NXF_VERSION=$(nextflow -version 2>&1 | head -1)
echo "      ${NXF_VERSION}"

# ── Run the pipeline ──────────────────────────────────────────────────────────
echo "[3/4] Launching pipeline…"
echo
nextflow run "${WORKFLOW_DIR}/workflows/protein_dynamics_ensemble.nf" \
    -profile  "${PROFILE}" \
    -work-dir "${NXF_WORK}" \
    --input_pdb  "${PDB_FILE}" \
    --n_samples  "${N_SAMPLES}" \
    --outdir     "${OUTDIR}" \
    -ansi-log    false

EXIT_CODE=$?
echo

# ── Report expected output paths ─────────────────────────────────────────────
echo "[4/4] Expected output paths"
echo "----------------------------------------------------------------------"
echo "  Conformational ensemble (tar.gz):"
echo "    ${OUTDIR}ensemble/1UBQ_ensemble.tar.gz"
echo
echo "  Pocket analysis (JSON):"
echo "    ${OUTDIR}pockets/1UBQ_pockets.json"
echo
echo "  Pocket visualisation (PDB, optional):"
echo "    ${OUTDIR}pockets/1UBQ_pockets.pdb"
echo
echo "  Summary report (JSON):"
echo "    ${OUTDIR}summary/summary_report.json"
echo
echo "  UMAP / distribution plot (PNG):"
echo "    ${OUTDIR}summary/conformational_umap.png"
echo "----------------------------------------------------------------------"

if [[ "${EXIT_CODE}" -eq 0 ]]; then
    echo "  STATUS: PASSED (exit 0)"

    # ── If running locally, do a quick output sanity check ────────────────────
    if [[ "${PROFILE}" == "local" && "${OUTDIR}" != s3://* ]]; then
        echo
        echo "Local output check:"
        for expected in \
            "${OUTDIR}/ensemble/1UBQ_ensemble.tar.gz" \
            "${OUTDIR}/pockets/1UBQ_pockets.json" \
            "${OUTDIR}/summary/summary_report.json" \
            "${OUTDIR}/summary/conformational_umap.png"
        do
            if [[ -f "${expected}" ]]; then
                SIZE=$(du -h "${expected}" | cut -f1)
                echo "  [OK]  ${expected}  (${SIZE})"
            else
                echo "  [MISSING]  ${expected}"
            fi
        done
    fi
else
    echo "  STATUS: FAILED (exit ${EXIT_CODE})"
    echo "  Check logs in: ${NXF_WORK}"
    exit "${EXIT_CODE}"
fi
