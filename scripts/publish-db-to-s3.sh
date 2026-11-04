#!/bin/bash
# publish-db-to-s3.sh — Internal BioMate tool.
# Uploads galaxy_ai_tools.db to the public S3 bucket used by on-prem deployments.
#
# Run once after each release that changes the workflow catalog, or when
# onboarding a new customer who needs the latest DB.
#
# Requires: aws CLI, sufficient IAM permissions on biomate-onprem-assets bucket.
#
# Usage:
#   bash scripts/publish-db-to-s3.sh [path/to/galaxy_ai_tools.db]
#   bash scripts/publish-db-to-s3.sh          # auto-discovers from running container

set -euo pipefail

BUCKET="biomate-onprem-assets"
REGION="us-west-2"
S3_KEY="onprem/galaxy_ai_tools.db"
PUBLIC_URL="https://${BUCKET}.s3.${REGION}.amazonaws.com/${S3_KEY}"

DB_PATH="${1:-}"

if [[ -z "$DB_PATH" ]]; then
  # Try to extract from a running Galaxy container
  if docker ps --format '{{.Names}}' | grep -q "galaxy"; then
    CONTAINER=$(docker ps --format '{{.Names}}' | grep "galaxy" | head -1)
    echo "Extracting DB from container $CONTAINER ..."
    DB_PATH="/tmp/galaxy_ai_tools_upload.db"
    docker cp "${CONTAINER}:/app/database/galaxy_ai_tools.db" "$DB_PATH"
  else
    echo "ERROR: No DB path given and no running Galaxy container found."
    echo "Usage: $0 /path/to/galaxy_ai_tools.db"
    exit 1
  fi
fi

if [[ ! -f "$DB_PATH" ]]; then
  echo "ERROR: DB file not found: $DB_PATH"
  exit 1
fi

SIZE=$(du -sh "$DB_PATH" | cut -f1)
echo "Uploading $DB_PATH ($SIZE) → s3://$BUCKET/$S3_KEY"

aws s3 cp "$DB_PATH" "s3://${BUCKET}/${S3_KEY}" \
  --region "$REGION" \
  --acl public-read \
  --content-type "application/octet-stream" \
  --metadata "source=biomate-release,date=$(date -u +%Y-%m-%d)"

echo ""
echo "Done. On-prem download URL:"
echo "  $PUBLIC_URL"
echo ""
echo "Update BIOMATE_DB_URL in docker-compose.onprem.yml or .env if you changed the path."
