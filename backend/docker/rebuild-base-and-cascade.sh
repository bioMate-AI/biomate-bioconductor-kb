#!/usr/bin/env bash
# rebuild-base-and-cascade.sh — rebuild biomate-nextflow-base + every image
# that FROM it, in topological order, to ship the numpy<2 pin across the
# cheminformatics tool chain.
#
# Why this exists:
#   The numpy<2 pin in aws_infrastructure/configs/Dockerfile.nextflow-base
#   (committed 2026-05-21) fixes the RDKit _ARRAY_API ABI mismatch that
#   crashed every cheminformatics workflow (canonical case: cyp_ddi_panel).
#   The fix only takes effect once the base + every image FROM it is
#   rebuilt and pushed to ECR with the new numpy pin.
#
# Topology (depth-first rebuild):
#   biomate-nextflow-base               (level 0, root)
#   ├── biomni-tools                    (level 1)
#   │   └── biomni-pharma               (level 2)
#   ├── biomni-admet                    (level 1, BASE_IMAGE param)
#   ├── biomni-structure-to-drug        (level 1)
#   ├── genomics-germline               (level 1)
#   ├── openfe-rbfe                     (level 1)
#   └── sra-tools                       (level 1)
#
# Usage:
#   ./backend/docker/rebuild-base-and-cascade.sh           # build + push amd64
#   ./backend/docker/rebuild-base-and-cascade.sh --dry-run # print steps only

set -euo pipefail

ECR="399683337364.dkr.ecr.us-west-2.amazonaws.com"
PLATFORM="linux/amd64"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date +%H:%M:%S)] $*"; }

run() {
  if $DRY_RUN; then
    echo "  DRY: $*"
  else
    "$@"
  fi
}

# ── ECR login ──────────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  log "ECR login (us-west-2)..."
  aws ecr get-login-password --region us-west-2 \
    | docker login --username AWS --password-stdin "$ECR" >/dev/null
fi

# ── Level 0: biomate-nextflow-base ─────────────────────────────────────────
log "=== [0/8] biomate-nextflow-base (root) ==="
run docker buildx build --platform "$PLATFORM" \
  -f aws_infrastructure/configs/Dockerfile.nextflow-base \
  -t "$ECR/biomate-nextflow-base:latest" \
  --push aws_infrastructure/configs/

# ── Level 1: direct children of biomate-nextflow-base ──────────────────────
build_l1() {
  local name="$1"
  log "=== biomni image: $name ==="
  run docker buildx build --platform "$PLATFORM" \
    -f "backend/docker/$name/Dockerfile" \
    -t "$ECR/biomate/$name:x86" \
    --push "backend/docker/$name/"
}

log "=== [1/8] biomni-tools ==="
build_l1 biomni-tools

log "=== [2/8] biomni-structure-to-drug ==="
build_l1 biomni-structure-to-drug

log "=== [3/8] genomics-germline ==="
build_l1 genomics-germline

log "=== [4/8] openfe-rbfe ==="
build_l1 openfe-rbfe

log "=== [5/8] sra-tools ==="
build_l1 sra-tools

# ── Level 1b: biomni-admet (uses BASE_IMAGE arg, defaults to nextflow-base) ─
log "=== [6/8] biomni-admet ==="
run docker buildx build --platform "$PLATFORM" \
  --build-arg "BASE_IMAGE=$ECR/biomate-nextflow-base:latest" \
  -f backend/docker/biomni-admet/Dockerfile \
  -t "$ECR/biomate/biomni-admet:x86" \
  --push backend/docker/biomni-admet/

# ── Level 2: biomni-pharma (FROM biomni-tools, must build AFTER biomni-tools) ─
log "=== [7/8] biomni-pharma (depends on biomni-tools) ==="
build_l1 biomni-pharma

log "=== [8/8] all rebuilds complete ==="
log "Smoke test: run cyp_ddi_panel on dev; it should no longer hit"
log "  AttributeError: _ARRAY_API not found"
log "  AttributeError: module 'rdkit.Chem.MolStandardize.rdMolStandardize' has no attribute 'Standardizer'"
log "Then trigger a fresh ADMET / Allometric / AutoDock sweep to confirm no"
log "regressions across the cohort that already passed."
