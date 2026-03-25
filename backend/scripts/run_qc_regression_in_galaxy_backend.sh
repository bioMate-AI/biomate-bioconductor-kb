#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "${BACKEND_DIR}/.." && pwd)"
IMAGE="${BIOMATE_GALAXY_BACKEND_IMAGE:-biomate-galaxy-backend}"

echo "[QC-DOCKER] Backend dir: ${BACKEND_DIR}"
echo "[QC-DOCKER] Image: ${IMAGE}"

if ! command -v docker >/dev/null 2>&1; then
  echo "[QC-DOCKER][ERROR] docker is required." >&2
  exit 1
fi

if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  echo "[QC-DOCKER] Image not found locally. Building via docker compose..."
  docker compose build galaxy-backend
fi

# Use mounted backend source as test target to avoid relying on image-internal test files.
docker run --rm \
  -v "${BACKEND_DIR}:/workspace" \
  -w /workspace \
  "${IMAGE}" \
  sh -lc '
    python -m pip show pytest >/dev/null 2>&1 || python -m pip install pytest
    python -m pip show rdkit-pypi >/dev/null 2>&1 || python -m pip install rdkit-pypi
    python -m pytest tests/test_qc_e2e_domains.py tests/test_qc_edge_cases.py -q
  '

echo "[QC-DOCKER] Backend QC regression suite passed."
