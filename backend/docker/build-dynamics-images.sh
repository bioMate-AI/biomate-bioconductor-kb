#!/bin/bash
# Build and push protein-dynamics-nf and cryo-heterogeneity-nf to ECR
# Run from repo root: bash backend/docker/build-dynamics-images.sh
set -euo pipefail

ECR="399683337364.dkr.ecr.us-west-2.amazonaws.com"
REGION="us-west-2"
PLATFORM="linux/amd64"

log() { echo "[$(date +'%H:%M:%S')] $1"; }

# ECR login
log "Logging in to ECR..."
aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$ECR"

build_push() {
    local name=$1
    local dir="backend/docker/${name}"
    local image="${ECR}/biomate/${name}:latest"

    log "Building $name ..."
    docker build --platform "$PLATFORM" \
        -t "biomate/${name}:latest" \
        -f "${dir}/Dockerfile" \
        "${dir}"

    log "Pushing $name to ECR ..."
    docker tag "biomate/${name}:latest" "$image"
    docker push "$image"
    log "Done: $image"
}

TARGET="${1:-both}"

case "$TARGET" in
    protein-dynamics-nf)   build_push protein-dynamics-nf ;;
    cryo-heterogeneity-nf) build_push cryo-heterogeneity-nf ;;
    both)
        build_push protein-dynamics-nf
        build_push cryo-heterogeneity-nf
        ;;
    *) echo "Usage: $0 [protein-dynamics-nf|cryo-heterogeneity-nf|both]"; exit 1 ;;
esac

log "All builds complete."
