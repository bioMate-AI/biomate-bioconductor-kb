#!/usr/bin/env bash
# test_cryo_heterogeneity.sh
#
# End-to-end test script for the Cryo-EM Conformational Heterogeneity pipeline.
#
# Steps:
#   1. Generate synthetic test data (particles .mrcs + CTF .pkl)
#   2. Upload test data to S3
#   3. Run Nextflow workflow on AWS Batch
#   4. Poll for completion and print output path
#
# Prerequisites:
#   - Python 3 with numpy, scipy, mrcfile installed
#   - AWS CLI configured (or running on an EC2/ECS instance with IAM role)
#   - Nextflow ≥ 23.04 on PATH
#   - AWS Batch queue 'biomate-nextflow-queue' accessible
#
# Usage:
#   cd backend/nf-core-workflows/modules/biomate-ai-tools/
#   bash test_data/test_cryo_heterogeneity.sh [--local]
#
# Pass --local to run with the local Docker executor (no AWS Batch).

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

S3_BUCKET="s3://biomate-nextflow-work"
S3_INPUT_PREFIX="${S3_BUCKET}/test-inputs/cryo-het"
S3_OUTPUT_PREFIX="${S3_BUCKET}/test-outputs/cryo-het"
S3_WORK_DIR="${S3_BUCKET}/work"

LOCAL_TEST_DATA="${SCRIPT_DIR}"
PARTICLES_FILE="${LOCAL_TEST_DATA}/cryo_het_test_particles.mrcs"
CTF_FILE="${LOCAL_TEST_DATA}/cryo_het_test_ctf.pkl"
POSES_FILE="${LOCAL_TEST_DATA}/cryo_het_test_poses.pkl"

# Reduced params for fast test run
N_ZDIM=2
N_EPOCHS=5
N_CLUSTERS=2

PROFILE="aws"
LOCAL_MODE=false

# ─── Parse flags ─────────────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --local)
            PROFILE="local"
            LOCAL_MODE=true
            ;;
    esac
done

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }

# ─── Step 1: Generate synthetic test data ────────────────────────────────────
log "Step 1: Generating synthetic cryo-EM test dataset..."

python3 "${SCRIPT_DIR}/generate_cryo_heterogeneity_test.py" \
    --outdir "${LOCAL_TEST_DATA}" \
    --n      50 \
    --box    64 \
    --seed   42

[[ -f "${PARTICLES_FILE}" ]] || fail "particles file not generated: ${PARTICLES_FILE}"
[[ -f "${CTF_FILE}"       ]] || fail "CTF file not generated: ${CTF_FILE}"
[[ -f "${POSES_FILE}"     ]] || fail "poses file not generated: ${POSES_FILE}"

log "  -> particles: ${PARTICLES_FILE}"
log "  -> ctf:       ${CTF_FILE}"
log "  -> poses:     ${POSES_FILE}"

# ─── Step 2: Upload to S3 (skip in local mode) ───────────────────────────────
if [[ "${LOCAL_MODE}" == "false" ]]; then
    log "Step 2: Uploading test data to S3..."

    AWS_CLI="${AWS_CLI:-/opt/aws-cli/bin/aws}"
    if ! command -v "${AWS_CLI}" &>/dev/null; then
        AWS_CLI="aws"   # fall back to PATH
    fi

    "${AWS_CLI}" s3 cp "${PARTICLES_FILE}" \
        "${S3_INPUT_PREFIX}/cryo_het_test_particles.mrcs" \
        --only-show-errors
    log "  -> uploaded particles to ${S3_INPUT_PREFIX}/cryo_het_test_particles.mrcs"

    "${AWS_CLI}" s3 cp "${CTF_FILE}" \
        "${S3_INPUT_PREFIX}/cryo_het_test_ctf.pkl" \
        --only-show-errors
    log "  -> uploaded CTF to ${S3_INPUT_PREFIX}/cryo_het_test_ctf.pkl"

    "${AWS_CLI}" s3 cp "${POSES_FILE}" \
        "${S3_INPUT_PREFIX}/cryo_het_test_poses.pkl" \
        --only-show-errors
    log "  -> uploaded poses to ${S3_INPUT_PREFIX}/cryo_het_test_poses.pkl"

    PARTICLES_ARG="${S3_INPUT_PREFIX}/cryo_het_test_particles.mrcs"
    CTF_ARG="${S3_INPUT_PREFIX}/cryo_het_test_ctf.pkl"
    POSES_ARG="${S3_INPUT_PREFIX}/cryo_het_test_poses.pkl"
    OUTDIR_ARG="${S3_OUTPUT_PREFIX}"
else
    log "Step 2: Skipping S3 upload (--local mode)"
    PARTICLES_ARG="${PARTICLES_FILE}"
    CTF_ARG="${CTF_FILE}"
    POSES_ARG="${POSES_FILE}"
    OUTDIR_ARG="${WORKFLOW_DIR}/results/cryo_het_test"
fi

# ─── Step 3: Run Nextflow workflow ────────────────────────────────────────────
log "Step 3: Launching Nextflow workflow (profile=${PROFILE})..."

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RUN_NAME="cryo-het-test-${TIMESTAMP}"
LOG_FILE="${SCRIPT_DIR}/nextflow_${RUN_NAME}.log"

NF_CMD=(
    nextflow run "${WORKFLOW_DIR}/workflows/cryo_em_heterogeneity.nf"
    -profile "${PROFILE}"
    -name    "${RUN_NAME}"
    --particles  "${PARTICLES_ARG}"
    --ctf        "${CTF_ARG}"
    --poses      "${POSES_ARG}"
    --n_zdim     "${N_ZDIM}"
    --n_epochs   "${N_EPOCHS}"
    --n_clusters "${N_CLUSTERS}"
    --outdir     "${OUTDIR_ARG}"
)

if [[ "${LOCAL_MODE}" == "false" ]]; then
    NF_CMD+=(
        -work-dir "${S3_WORK_DIR}/cryo-het-test/${TIMESTAMP}"
    )
fi

log "  Command: ${NF_CMD[*]}"
log "  Logfile: ${LOG_FILE}"
echo ""

# Run in foreground so we capture exit code; tee to logfile
"${NF_CMD[@]}" 2>&1 | tee "${LOG_FILE}"
NF_EXIT=${PIPESTATUS[0]}

# ─── Step 4: Report results ──────────────────────────────────────────────────
echo ""
if [[ "${NF_EXIT}" -eq 0 ]]; then
    log "Workflow COMPLETED successfully."
    echo ""
    log "Output location: ${OUTDIR_ARG}"

    if [[ "${LOCAL_MODE}" == "false" ]]; then
        log "Listing output files:"
        "${AWS_CLI:-aws}" s3 ls "${OUTDIR_ARG}/" --recursive 2>/dev/null | \
            awk '{print "  " $4}' || true
    else
        log "Listing output files:"
        find "${OUTDIR_ARG}" -type f 2>/dev/null | awk '{print "  " $0}' | head -20 || true
    fi

    echo ""
    log "Key outputs to check:"
    log "  heterogeneity_report.json — n_states, population_fractions, top druggable state"
    log "  umap.png                  — UMAP of particle latent space"
    log "  vol_*.mrc                 — representative 3D density maps"
    log "  ensemble_pockets.json     — per-state pocket druggability"
else
    fail "Workflow FAILED (exit code ${NF_EXIT}). See log: ${LOG_FILE}"
fi
