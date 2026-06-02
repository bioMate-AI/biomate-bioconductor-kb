#!/usr/bin/env bash
# Build and push ambertools-gromacs-nf ECR image (v1.2.0 — OpenMPI for gmx_MMPBSA).
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
ACCOUNT="${AWS_ACCOUNT_ID:-399683337364}"
REPO="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/biomate/ambertools-gromacs-nf"
TAG="${1:-1.2.0}"
DOCKERFILE_DIR="$(cd "$(dirname "$0")/../../backend/docker/ambertools-gromacs-nf" && pwd)"

echo "Building ${REPO}:${TAG} from ${DOCKERFILE_DIR}"
docker build --platform linux/amd64 -t "biomate/ambertools-gromacs-nf:${TAG}" "${DOCKERFILE_DIR}"

aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

docker tag "biomate/ambertools-gromacs-nf:${TAG}" "${REPO}:${TAG}"
docker tag "biomate/ambertools-gromacs-nf:${TAG}" "${REPO}:latest"
docker push "${REPO}:${TAG}"
docker push "${REPO}:latest"

echo "Pushed ${REPO}:${TAG} and :latest"
echo "Re-run MM-GBSA: research/anti-virus/scripts/run_mmgbsa_standalone_batch.sh"
