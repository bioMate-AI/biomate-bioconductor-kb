#!/usr/bin/env bash
# Run ON EC2 (BioMate-Production or any amd64 host with Docker + instance profile ECR push).
set -euo pipefail
exec > /tmp/ecr_build_ambertools.log 2>&1

echo "START $(date -u +%Y%m%dT%H%M%SZ)"
REGION="${AWS_REGION:-us-west-2}"
ACCOUNT="${AWS_ACCOUNT_ID:-399683337364}"
REPO="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com/biomate/ambertools-gromacs-nf"
TAG="${1:-1.2.0}"
WORKDIR="/tmp/ambertools-gromacs-nf-build-${TAG}"

rm -rf "${WORKDIR}"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

S3_PREFIX="s3://biomate-nextflow-work/dev-sync/build"
aws s3 cp "${S3_PREFIX}/ambertools-gromacs-nf-${TAG}.tar.gz" . --region "${REGION}"
tar xzf "ambertools-gromacs-nf-${TAG}.tar.gz"

echo "Docker build ${TAG}..."
docker build --platform linux/amd64 -t "biomate/ambertools-gromacs-nf:${TAG}" ambertools-gromacs-nf

aws ecr get-login-password --region "${REGION}" | \
  docker login --username AWS --password-stdin "${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

docker tag "biomate/ambertools-gromacs-nf:${TAG}" "${REPO}:${TAG}"
docker tag "biomate/ambertools-gromacs-nf:${TAG}" "${REPO}:latest"
docker push "${REPO}:${TAG}"
docker push "${REPO}:latest"

echo "Smoke test..."
docker run --rm "${REPO}:${TAG}" python3 -c "from mpi4py import MPI; import GMXMMPBSA; print('MPI+GMXMMPBSA OK')"
docker run --rm "${REPO}:${TAG}" gmx_MMPBSA --version || true
docker run --rm "${REPO}:${TAG}" /opt/aws-cli/bin/aws --version

echo "DONE $(date -u +%Y%m%dT%H%M%SZ) pushed ${REPO}:${TAG} and :latest"
