#!/bin/bash
#
# BioMate Database Files Download Script
# Downloads required database files from S3
#

set -e

echo "=========================================="
echo "BioMate Database Files Download"
echo "=========================================="
echo ""

# Check if running from backend directory
if [ ! -f "run.sh" ]; then
    echo "ERROR: This script must be run from the backend directory"
    echo "Usage: cd backend && ./download_databases.sh"
    exit 1
fi

# S3 bucket and paths
S3_BUCKET="galaxy-cloud-data-1760241377"
S3_PREFIX="biomate"

# File 1: galaxy_ai_tools.db (130 MB)
DB_FILE="galaxy_ai_tools.db"
DB_PATH="${DB_FILE}"
DB_SIZE="130 MB"

# File 2: all_unique_tools.json (69 MB)
JSON_FILE="all_unique_tools.json"
JSON_PATH="database/${JSON_FILE}"
JSON_SIZE="69 MB"

echo "This script will download:"
echo "  1. ${DB_FILE} (${DB_SIZE}) → ${DB_PATH}"
echo "  2. ${JSON_FILE} (${JSON_SIZE}) → ${JSON_PATH}"
echo ""
echo "Total download size: ~199 MB"
echo ""

# Check if files already exist
if [ -f "${DB_PATH}" ] && [ -f "${JSON_PATH}" ]; then
    read -p "Files already exist. Re-download? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Download cancelled."
        exit 0
    fi
fi

# Check for AWS CLI
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI not found"
    echo ""
    echo "Install AWS CLI:"
    echo "  macOS:   brew install awscli"
    echo "  Linux:   sudo apt-get install awscli"
    echo "  Windows: https://aws.amazon.com/cli/"
    echo ""
    exit 1
fi

# Create database directory if needed
mkdir -p database

echo "Downloading database files from S3..."
echo ""

# Download galaxy_ai_tools.db
echo "[1/2] Downloading ${DB_FILE}..."
if aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${DB_FILE}" "${DB_PATH}"; then
    echo "✓ Downloaded ${DB_FILE}"
else
    echo "✗ Failed to download ${DB_FILE}"
    exit 1
fi
echo ""

# Download all_unique_tools.json
echo "[2/2] Downloading ${JSON_FILE}..."
if aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${JSON_FILE}" "${JSON_PATH}"; then
    echo "✓ Downloaded ${JSON_FILE}"
else
    echo "✗ Failed to download ${JSON_FILE}"
    exit 1
fi
echo ""

# Verify files
echo "Verifying downloads..."
if [ ! -f "${DB_PATH}" ]; then
    echo "✗ ${DB_PATH} not found"
    exit 1
fi

if [ ! -f "${JSON_PATH}" ]; then
    echo "✗ ${JSON_PATH} not found"
    exit 1
fi

DB_ACTUAL_SIZE=$(du -h "${DB_PATH}" | cut -f1)
JSON_ACTUAL_SIZE=$(du -h "${JSON_PATH}" | cut -f1)

echo "✓ ${DB_FILE} (${DB_ACTUAL_SIZE})"
echo "✓ ${JSON_FILE} (${JSON_ACTUAL_SIZE})"
echo ""

echo "=========================================="
echo "Download complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Configure API keys: cp .env.template .env"
echo "  2. Edit .env with your Anthropic API key"
echo "  3. Start Galaxy: ./run.sh"
echo ""
