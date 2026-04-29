#!/bin/bash
# Build and push pharmacology Docker images to ECR.
#
# Usage:
#   ./backend/docker/build-pharma-images.sh               # build all three
#   ./backend/docker/build-pharma-images.sh biomni-admet
#   ./backend/docker/build-pharma-images.sh biomni-pharma
#   ./backend/docker/build-pharma-images.sh r-pharma
#
# Prerequisites:
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com

set -euo pipefail

ECR="399683337364.dkr.ecr.us-west-2.amazonaws.com"

build_biomni_admet() {
    echo "=== Building biomni-admet:x86 ==="
    # From biomate-nextflow-base (NOT biomni-tools) — lean ADMET-specific image
    docker buildx build \
        --platform linux/amd64 \
        --progress=plain \
        -t "$ECR/biomate/biomni-admet:x86" \
        --push \
        -f backend/docker/biomni-admet/Dockerfile \
        .
    echo "biomni-admet pushed to $ECR/biomate/biomni-admet:x86"
}

build_biomni_pharma() {
    echo "=== Building biomni-pharma:x86 ==="
    # From biomni-tools — adds py2opsin, molfeat, chembl client
    docker buildx build \
        --platform linux/amd64 \
        --progress=plain \
        -t "$ECR/biomate/biomni-pharma:x86" \
        --push \
        -f backend/docker/biomni-pharma/Dockerfile \
        .
    echo "biomni-pharma pushed to $ECR/biomate/biomni-pharma:x86"
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
    biomni-admet)  build_biomni_admet ;;
    biomni-pharma) build_biomni_pharma ;;
    r-pharma)      build_r_pharma ;;
    all)
        build_biomni_admet
        build_biomni_pharma
        build_r_pharma
        echo ""
        echo "=== All pharmacology images built and pushed ==="
        echo "  $ECR/biomate/biomni-admet:x86   (ADMET-AI/Chemprop — from base)"
        echo "  $ECR/biomate/biomni-pharma:x86  (py2opsin/molfeat — from biomni-tools)"
        echo "  $ECR/biomate/r-pharma:x86       (nlmixr2/PKNCA — from rocker)"
        ;;
    *) echo "Unknown target: $TARGET. Use: biomni-admet | biomni-pharma | r-pharma | all" ; exit 1 ;;
esac
