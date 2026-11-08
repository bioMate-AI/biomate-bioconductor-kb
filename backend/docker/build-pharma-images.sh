#!/bin/bash
# Build and push pharmacology Docker images to ECR.
#
# Usage:
#   ./backend/docker/build-pharma-images.sh               # build all three
#   ./backend/docker/build-pharma-images.sh admet
#   ./backend/docker/build-pharma-images.sh pharmacology-tools
#   ./backend/docker/build-pharma-images.sh r-pharma
#
# Prerequisites:
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com

set -euo pipefail

ECR="399683337364.dkr.ecr.us-west-2.amazonaws.com"

build_biomni_admet() {
    echo "=== Building admet:x86 ==="
    # From biomate/nextflow-base (NOT workflow-tools) — lean ADMET-specific image
    docker buildx build \
        --platform linux/amd64 \
        --progress=plain \
        -t "$ECR/biomate/admet:x86" \
        --push \
        -f backend/docker/admet/Dockerfile \
        .
    echo "admet pushed to $ECR/biomate/admet:x86"
}

build_biomni_pharma() {
    echo "=== Building pharmacology-tools:x86 ==="
    # From workflow-tools — adds py2opsin, molfeat, chembl client
    docker buildx build \
        --platform linux/amd64 \
        --progress=plain \
        -t "$ECR/biomate/pharmacology-tools:x86" \
        --push \
        -f backend/docker/pharmacology-tools/Dockerfile \
        .
    echo "pharmacology-tools pushed to $ECR/biomate/pharmacology-tools:x86"
}

build_r_pharma() {
    echo "=== Building r-pharma:x86 ==="
    docker buildx build \
        --platform linux/amd64 \
        --progress=plain \
        -t "$ECR/biomate/r-pharma:x86" \
        --push \
        -f backend/docker/r-pharma/Dockerfile \
        .
    echo "r-pharma pushed to $ECR/biomate/r-pharma:x86"
}

TARGET="${1:-all}"

case "$TARGET" in
    admet)  build_biomni_admet ;;
    pharmacology-tools) build_biomni_pharma ;;
    r-pharma)      build_r_pharma ;;
    all)
        build_biomni_admet
        build_biomni_pharma
        build_r_pharma
        echo ""
        echo "=== All pharmacology images built and pushed ==="
        echo "  $ECR/biomate/admet:x86   (ADMET-AI/Chemprop — from base)"
        echo "  $ECR/biomate/pharmacology-tools:x86  (py2opsin/molfeat — from workflow-tools)"
        echo "  $ECR/biomate/r-pharma:x86       (nlmixr2/PKNCA — from rocker)"
        ;;
    *) echo "Unknown target: $TARGET. Use: admet | pharmacology-tools | r-pharma | all" ; exit 1 ;;
esac
