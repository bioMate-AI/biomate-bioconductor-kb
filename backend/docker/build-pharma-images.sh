#!/bin/bash
# Build and push pharmacology Docker images to ECR.
#
# Usage:
#   ./backend/docker/build-pharma-images.sh            # build both
#   ./backend/docker/build-pharma-images.sh biomni-pharma
#   ./backend/docker/build-pharma-images.sh r-pharma
#
# Prerequisites:
#   aws ecr get-login-password --region us-west-2 | \
#     docker login --username AWS --password-stdin 399683337364.dkr.ecr.us-west-2.amazonaws.com

set -euo pipefail

ECR="399683337364.dkr.ecr.us-west-2.amazonaws.com"
REGION="us-west-2"

build_biomni_pharma() {
    echo "=== Building biomni-pharma:x86 ==="
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
    # r-pharma does NOT pull from ECR base, it uses rocker/r-ver:4.3.1
    # No ECR login needed for the base, but ECR push still requires auth.
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
    biomni-pharma) build_biomni_pharma ;;
    r-pharma)      build_r_pharma ;;
    all)
        build_biomni_pharma
        build_r_pharma
        echo ""
        echo "=== All pharmacology images built and pushed ==="
        echo "  $ECR/biomate/biomni-pharma:x86"
        echo "  $ECR/biomate/r-pharma:x86"
        ;;
    *) echo "Unknown target: $TARGET. Use: biomni-pharma | r-pharma | all" ; exit 1 ;;
esac
