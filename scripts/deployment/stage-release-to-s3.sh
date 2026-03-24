#!/usr/bin/env bash
set -euo pipefail

# Stage a release bundle and optional large assets to S3.
#
# Usage:
#   ./scripts/deployment/stage-release-to-s3.sh \
#     --bucket biomate-nextflow-work \
#     --release-id aws-release-2026-03-12-r1 \
#     [--region us-west-2] \
#     [--asset-manifest ./release-assets.tsv]
#
# asset-manifest format (tab-separated, no header):
#   /absolute/or/relative/local/path<TAB>s3/object/key

usage() {
  cat <<'EOF'
Usage:
  stage-release-to-s3.sh --bucket <bucket> --release-id <id> [--region <aws-region>] [--asset-manifest <path>]

Required:
  --bucket          S3 bucket to store release artifacts
  --release-id      Release identifier (for example aws-release-2026-03-12-r1)

Optional:
  --region          AWS region (defaults to AWS_DEFAULT_REGION or us-west-2)
  --asset-manifest  TSV file listing large files to upload first (path<TAB>s3-key)
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
ASSET_MANIFEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET="$2"; shift 2 ;;
    --release-id)
      RELEASE_ID="$2"; shift 2 ;;
    --region)
      REGION="$2"; shift 2 ;;
    --asset-manifest)
      ASSET_MANIFEST="$2"; shift 2 ;;
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

require_cmd git
require_cmd aws
require_cmd tar
require_cmd sha256sum

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: run this script from inside the repository" >&2
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS credentials are not configured or invalid" >&2
  exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

S3_PREFIX="releases/${RELEASE_ID}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCHIVE_PATH="${TMP_DIR}/source.tar.gz"
SHA_PATH="${TMP_DIR}/source.tar.gz.sha256"
MANIFEST_PATH="${TMP_DIR}/release-manifest.txt"

COMMIT_SHA="$(git rev-parse HEAD)"
TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "==> Creating source archive from commit ${COMMIT_SHA}"
git archive --format=tar.gz --output "$ARCHIVE_PATH" HEAD
sha256sum "$ARCHIVE_PATH" > "$SHA_PATH"

echo "==> Uploading source archive to s3://${BUCKET}/${S3_PREFIX}/"
aws s3 cp "$ARCHIVE_PATH" "s3://${BUCKET}/${S3_PREFIX}/source.tar.gz" --region "$REGION"
aws s3 cp "$SHA_PATH" "s3://${BUCKET}/${S3_PREFIX}/source.tar.gz.sha256" --region "$REGION"

{
  echo "release_id=${RELEASE_ID}"
  echo "timestamp_utc=${TIMESTAMP_UTC}"
  echo "commit_sha=${COMMIT_SHA}"
  echo "source_archive=s3://${BUCKET}/${S3_PREFIX}/source.tar.gz"
  echo "source_archive_sha256=s3://${BUCKET}/${S3_PREFIX}/source.tar.gz.sha256"
} > "$MANIFEST_PATH"

if [[ -n "$ASSET_MANIFEST" ]]; then
  if [[ ! -f "$ASSET_MANIFEST" ]]; then
    echo "ERROR: asset manifest not found: $ASSET_MANIFEST" >&2
    exit 1
  fi

  echo "==> Uploading large assets from manifest: $ASSET_MANIFEST"
  ASSET_COUNT=0
  while IFS=$'\t' read -r LOCAL_PATH S3_KEY; do
    [[ -z "${LOCAL_PATH}" ]] && continue
    [[ "${LOCAL_PATH}" =~ ^# ]] && continue
    if [[ -z "${S3_KEY}" ]]; then
      echo "ERROR: malformed line in asset manifest (missing s3 key): ${LOCAL_PATH}" >&2
      exit 1
    fi
    if [[ ! -e "$LOCAL_PATH" ]]; then
      echo "ERROR: asset not found: $LOCAL_PATH" >&2
      exit 1
    fi
    DEST_KEY="assets/${RELEASE_ID}/${S3_KEY}"
    echo "   -> ${LOCAL_PATH} => s3://${BUCKET}/${DEST_KEY}"
    aws s3 cp "$LOCAL_PATH" "s3://${BUCKET}/${DEST_KEY}" --region "$REGION"
    echo "asset_${ASSET_COUNT}=s3://${BUCKET}/${DEST_KEY}" >> "$MANIFEST_PATH"
    ASSET_COUNT=$((ASSET_COUNT + 1))
  done < "$ASSET_MANIFEST"
  echo "asset_count=${ASSET_COUNT}" >> "$MANIFEST_PATH"
fi

aws s3 cp "$MANIFEST_PATH" "s3://${BUCKET}/${S3_PREFIX}/release-manifest.txt" --region "$REGION"

echo
echo "Staging complete."
echo "  Release ID: ${RELEASE_ID}"
echo "  Source: s3://${BUCKET}/${S3_PREFIX}/source.tar.gz"
echo "  Manifest: s3://${BUCKET}/${S3_PREFIX}/release-manifest.txt"
