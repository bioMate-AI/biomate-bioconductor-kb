#!/usr/bin/env bash
set -euo pipefail

# Deploy BioMate to EC2 via Docker using a source archive staged in S3.
#
# Run this ON EC2.
#
# Usage:
#   sudo bash scripts/deployment/ec2-deploy-from-s3.sh \
#     --bucket biomate-nextflow-work \
#     --release-id aws-release-2026-03-12-r1 \
#     [--region us-west-2] \
#     [--assets-prefix assets/aws-release-2026-03-12-r1] \
#     [--assets-dir /opt/biomate/shared/assets]

usage() {
  cat <<'EOF'
Usage:
  ec2-deploy-from-s3.sh --bucket <bucket> --release-id <id> [--region <aws-region>] [--assets-prefix <prefix>] [--assets-dir <dir>]

Required:
  --bucket        S3 bucket containing staged release artifacts
  --release-id    Release identifier

Optional:
  --region        AWS region (defaults to AWS_DEFAULT_REGION or us-west-2)
  --assets-prefix S3 prefix to sync large assets from (for example assets/<release-id>)
  --assets-dir    Local directory for synced large assets (default /opt/biomate/shared/assets)
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command '$1'" >&2
    exit 1
  }
}

BUCKET=""
RELEASE_ID=""
REGION="${AWS_DEFAULT_REGION:-us-west-2}"
ASSETS_PREFIX=""
ASSETS_DIR="/opt/biomate/shared/assets"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET="$2"; shift 2 ;;
    --release-id)
      RELEASE_ID="$2"; shift 2 ;;
    --region)
      REGION="$2"; shift 2 ;;
    --assets-prefix)
      ASSETS_PREFIX="$2"; shift 2 ;;
    --assets-dir)
      ASSETS_DIR="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$BUCKET" || -z "$RELEASE_ID" ]]; then
  echo "ERROR: --bucket and --release-id are required" >&2
  usage
  exit 1
fi

require_cmd aws
require_cmd tar
require_cmd sha256sum

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials/role not available on this EC2 instance" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing Docker engine"
  apt-get update
  apt-get install -y docker.io docker-compose-v2
  systemctl enable --now docker
fi

BASE_DIR="/opt/biomate"
RELEASE_DIR="${BASE_DIR}/releases/${RELEASE_ID}"
SHARED_DIR="${BASE_DIR}/shared"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$RELEASE_DIR" "$SHARED_DIR" "$ASSETS_DIR"

ARCHIVE_LOCAL="${TMP_DIR}/source.tar.gz"
SHA_LOCAL="${TMP_DIR}/source.tar.gz.sha256"
S3_PREFIX="releases/${RELEASE_ID}"

echo "==> Downloading release archive"
aws s3 cp "s3://${BUCKET}/${S3_PREFIX}/source.tar.gz" "$ARCHIVE_LOCAL" --region "$REGION"
aws s3 cp "s3://${BUCKET}/${S3_PREFIX}/source.tar.gz.sha256" "$SHA_LOCAL" --region "$REGION"

echo "==> Verifying archive checksum"
(cd "$TMP_DIR" && sha256sum -c source.tar.gz.sha256)

echo "==> Extracting release to ${RELEASE_DIR}"
tar -xzf "$ARCHIVE_LOCAL" -C "$RELEASE_DIR"

ln -sfn "$RELEASE_DIR" "${BASE_DIR}/current"

if [[ -n "$ASSETS_PREFIX" ]]; then
  echo "==> Syncing large assets from s3://${BUCKET}/${ASSETS_PREFIX} to ${ASSETS_DIR}"
  aws s3 sync "s3://${BUCKET}/${ASSETS_PREFIX}" "$ASSETS_DIR" --region "$REGION"
fi

if [[ ! -f "${SHARED_DIR}/.env.ec2" ]]; then
  echo "ERROR: ${SHARED_DIR}/.env.ec2 not found." >&2
  echo "Create it before starting containers. Example:" >&2
  echo "  cp ${BASE_DIR}/current/.env.ec2.example ${SHARED_DIR}/.env.ec2" >&2
  exit 1
fi

VALIDATOR="${BASE_DIR}/current/scripts/deployment/validate-ec2-config.sh"
if [[ ! -f "$VALIDATOR" ]]; then
  echo "ERROR: config validator missing: $VALIDATOR" >&2
  exit 1
fi
chmod +x "$VALIDATOR"
echo "==> Validating required EC2 config"
bash "$VALIDATOR" \
  --env-file "${SHARED_DIR}/.env.ec2" \
  --repo-root "${BASE_DIR}/current"

COMPOSE_FILE="${BASE_DIR}/current/docker-compose.ec2.yml"
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: compose file missing: $COMPOSE_FILE" >&2
  exit 1
fi

echo "==> Pulling/building and starting containers"
docker compose \
  -f "$COMPOSE_FILE" \
  --env-file "${SHARED_DIR}/.env.ec2" \
  up -d --build

echo "==> Deployment status"
docker compose -f "$COMPOSE_FILE" ps

echo
echo "EC2 Docker deployment complete for release ${RELEASE_ID}"
echo "Current symlink: ${BASE_DIR}/current -> ${RELEASE_DIR}"
