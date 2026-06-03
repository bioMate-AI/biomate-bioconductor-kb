#!/bin/bash
# Build and push per-workflow virtual_cell + single_cell Docker images to ECR.
#
# Per CLAUDE.md / Gap-3 (runtime pip → bake-in) + Gap-4 (8 untested GPU images).
# Each image is workflow-scoped and pinned to linux/amd64 for AWS Batch.
#
# Usage:
#   ./backend/docker/build-virtual-cell-images.sh                # all 11
#   ./backend/docker/build-virtual-cell-images.sh cpu            # 3 CPU only
#   ./backend/docker/build-virtual-cell-images.sh gpu            # 8 GPU only
#   ./backend/docker/build-virtual-cell-images.sh <image-name>   # one specific
#
# Prerequisites:
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com

set -uo pipefail   # not -e: we want to continue past one failure and report the full sweep

ECR="399683337364.dkr.ecr.us-west-2.amazonaws.com"
TAG="1.0"

CPU_IMAGES=(
  "ode-signaling-nf"
  "transcriptomic-moa-lincs-nf"
  "virtual-patient-cohort-nf"
)

GPU_IMAGES=(
  # state_perturbation_prediction reuses biomate/ai-tools/state (already in ECR;
  # built via backend/docker/biomate-ai-tools/build-ecr.sh state)
  "cpa-drug-combination-synergy-gpu-nf"
  "cpa-synergy-gpu-nf"
  "gears-perturbation-gpu-nf"
  "gears-perturbation-prediction-gpu-nf"
  "physicell-tumor-tgi-nf"
  "transcriptformer-cell-state-gpu-nf"
  "transcriptformer-gpu-nf"
)

build_one() {
    local name="$1"
    local dockerfile="backend/docker/${name}/Dockerfile"
    if [ ! -f "$dockerfile" ]; then
        echo "[SKIP] ${name}: ${dockerfile} not found" >&2
        return 2
    fi
    local image_tag="${ECR}/biomate/${name}:${TAG}"
    echo "=== Building ${name} → ${image_tag} ==="
    # Refresh ECR auth before each build — token expires; buildx auth state can also
    # be lost between builds (--push runs in a separate worker).
    aws ecr get-login-password --region us-west-2 \
        | docker login --username AWS --password-stdin "${ECR}" >/dev/null 2>&1 \
        || { echo "[FAIL] ${name}: ECR login failed" >&2; return 1; }
    local start_ts
    start_ts=$(date +%s)
    if docker buildx build \
        --platform linux/amd64 \
        --progress=plain \
        -t "${image_tag}" \
        --push \
        -f "${dockerfile}" \
        . ; then
        local dur=$(( $(date +%s) - start_ts ))
        echo "[OK] ${name} in ${dur}s"
        return 0
    else
        echo "[FAIL] ${name}" >&2
        return 1
    fi
}

run_set() {
    local -n imgs="$1"
    local ok=() failed=() skipped=()
    for img in "${imgs[@]}"; do
        rc=0
        build_one "$img" || rc=$?
        case $rc in
            0) ok+=("$img") ;;
            2) skipped+=("$img") ;;
            *) failed+=("$img") ;;
        esac
    done
    echo
    echo "=== SUMMARY ==="
    echo "OK      (${#ok[@]}):      ${ok[*]:-}"
    echo "FAILED  (${#failed[@]}):  ${failed[*]:-}"
    echo "SKIPPED (${#skipped[@]}): ${skipped[*]:-}"
    [ "${#failed[@]}" -eq 0 ]
}

target="${1:-all}"
case "$target" in
    all)
        all=("${CPU_IMAGES[@]}" "${GPU_IMAGES[@]}")
        run_set all
        ;;
    cpu)
        run_set CPU_IMAGES
        ;;
    gpu)
        run_set GPU_IMAGES
        ;;
    *)
        only=("$target")
        run_set only
        ;;
esac
