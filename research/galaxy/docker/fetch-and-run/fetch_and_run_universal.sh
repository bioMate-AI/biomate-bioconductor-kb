#!/bin/bash
#
# Universal Galaxy Cloud Executor - Fetch and Run Script
#
# This script creates a consistent execution environment for ANY Galaxy tool.
# It does NOT require special-casing individual tools.
#
# Core Principle: Environment Consistency > Command Rewriting
#
# Container Directory Structure:
#   /galaxy_execution/
#   ├── job/                    # Job root
#   │   ├── working/           # Working directory (execution starts here)
#   │   ├── inputs/            # Input files
#   │   ├── outputs/           # Output files
#   │   ├── configs/           # Config files
#   │   └── metadata/          # Metadata
#   └── datasets/              # Dataset storage
#       └── objects/           # Dataset objects (hash-based paths)

set -e  # Exit on error

# ============================================================================
# Configuration from Environment
# ============================================================================

AWS_REGION=${AWS_REGION:-us-west-2}
S3_BUCKET=${S3_BUCKET:-galaxy-cloud-data}
JOB_ID=${JOB_ID:-unknown}
JOB_SCRIPT_S3_URL=${JOB_SCRIPT_S3_URL}
TOOL_CONTAINER_IMAGE=${TOOL_CONTAINER_IMAGE}  # Optional: tool-specific container

# ============================================================================
# Container Directory Structure (FIXED, STANDARD)
# ============================================================================

EXECUTION_ROOT="/galaxy_execution"
JOB_DIR="$EXECUTION_ROOT/job"
WORK_DIR="$JOB_DIR/working"
INPUT_DIR="$JOB_DIR/inputs"
OUTPUT_DIR="$JOB_DIR/outputs"
CONFIG_DIR="$JOB_DIR/configs"
METADATA_DIR="$JOB_DIR/metadata"
DATASETS_ROOT="$EXECUTION_ROOT/datasets"
OBJECTS_DIR="$DATASETS_ROOT/objects"

# Job script location
SCRIPT_FILE="$JOB_DIR/job_script.sh"

# ============================================================================
# Startup Banner
# ============================================================================

echo "========================================================================"
echo "Galaxy Universal Cloud Executor"
echo "========================================================================"
echo "Job ID: ${JOB_ID}"
echo "S3 Bucket: ${S3_BUCKET}"
echo "AWS Region: ${AWS_REGION}"
echo "Script URL: ${JOB_SCRIPT_S3_URL}"
echo "Tool Container: ${TOOL_CONTAINER_IMAGE:-none (direct execution)}"
echo "========================================================================"
echo ""

# ============================================================================
# AWS Credentials Verification
# ============================================================================

echo "Checking AWS credentials..."
if [ -n "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}" ]; then
    echo "[OK] Using ECS task role credentials"
    echo "  URI: ${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI}"
else
    echo "[WARN] No ECS task role credentials found"
fi

# Verify AWS identity
echo "AWS Identity:"
aws sts get-caller-identity --region "${AWS_REGION}" || {
    echo "ERROR: Cannot get AWS identity"
    exit 1
}
echo ""

# ============================================================================
# Step 1: Create Standard Directory Structure
# ============================================================================

echo "[1/5] Creating standard directory structure..."
mkdir -p "$WORK_DIR" "$INPUT_DIR" "$OUTPUT_DIR" "$CONFIG_DIR" "$METADATA_DIR" "$OBJECTS_DIR"
echo "[OK] Directory structure created"
echo "  Job dir: $JOB_DIR"
echo "  Work dir: $WORK_DIR"
echo "  Datasets: $DATASETS_ROOT"
echo ""

# ============================================================================
# Step 2: Download Job Files from S3
# ============================================================================

echo "[2/5] Downloading job files from S3..."

# Download job script
if [ -z "${JOB_SCRIPT_S3_URL}" ]; then
    echo "ERROR: JOB_SCRIPT_S3_URL not set"
    exit 1
fi

aws s3 cp "${JOB_SCRIPT_S3_URL}" "${SCRIPT_FILE}" --region "${AWS_REGION}"
chmod +x "${SCRIPT_FILE}"
echo "[OK] Job script downloaded"

# Download ALL job files using sync
# This is the key to universality: we don't need to know what files exist,
# we just download everything and put it in the right place

S3_JOB_PREFIX="s3://${S3_BUCKET}/jobs/${JOB_ID}/"

# Download to temporary location first to avoid conflicts with job_script.sh
TMP_DOWNLOAD="/tmp/job_download_${JOB_ID}"
mkdir -p "$TMP_DOWNLOAD"

echo "  Downloading all job files..."
aws s3 sync "${S3_JOB_PREFIX}" "$TMP_DOWNLOAD/" \
    --region "${AWS_REGION}" \
    --exclude "job_script.sh" \
    --quiet || echo "[WARN] Some files may not exist (this is normal)"

# Distribute files to correct locations based on directory structure
# inputs/* → INPUT_DIR
if [ -d "$TMP_DOWNLOAD/inputs" ]; then
    echo "  Processing input files..."
    rsync -a "$TMP_DOWNLOAD/inputs/" "$INPUT_DIR/" 2>/dev/null || true
    INPUT_COUNT=$(find "$INPUT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] $INPUT_COUNT input file(s)"
fi

# working/* → WORK_DIR
if [ -d "$TMP_DOWNLOAD/working" ]; then
    echo "  Processing working files..."
    rsync -a "$TMP_DOWNLOAD/working/" "$WORK_DIR/" 2>/dev/null || true
    WORKING_COUNT=$(find "$WORK_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] $WORKING_COUNT working file(s)"
fi

# configs/* → CONFIG_DIR
if [ -d "$TMP_DOWNLOAD/configs" ]; then
    echo "  Processing config files..."
    rsync -a "$TMP_DOWNLOAD/configs/" "$CONFIG_DIR/" 2>/dev/null || true
fi

# metadata/* → METADATA_DIR
if [ -d "$TMP_DOWNLOAD/metadata" ]; then
    echo "  Processing metadata files..."
    rsync -a "$TMP_DOWNLOAD/metadata/" "$METADATA_DIR/" 2>/dev/null || true
fi

# datasets/objects/* → OBJECTS_DIR (if any pre-staged datasets)
if [ -d "$TMP_DOWNLOAD/datasets/objects" ]; then
    echo "  Processing dataset objects..."
    rsync -a "$TMP_DOWNLOAD/datasets/objects/" "$OBJECTS_DIR/" 2>/dev/null || true
fi

# Cleanup temp download
rm -rf "$TMP_DOWNLOAD"

echo "[OK] All job files downloaded and organized"
echo ""

# ============================================================================
# Step 3: Set Up Execution Environment
# ============================================================================

echo "[3/5] Setting up execution environment..."

# Export standard environment variables
export GALAXY_EXECUTION_ROOT="$EXECUTION_ROOT"
export GALAXY_JOB_DIR="$JOB_DIR"
export GALAXY_WORK_DIR="$WORK_DIR"
export GALAXY_INPUT_DIR="$INPUT_DIR"
export GALAXY_OUTPUT_DIR="$OUTPUT_DIR"
export GALAXY_CONFIG_DIR="$CONFIG_DIR"
export GALAXY_DATASETS_ROOT="$DATASETS_ROOT"

# Debug: Show environment
echo "  Environment variables set:"
env | grep "^GALAXY_" | sed 's/^/    /'

# Change to working directory (default execution location)
cd "$WORK_DIR"
echo "  Working directory: $(pwd)"
echo "[OK] Environment ready"
echo ""

# ============================================================================
# Step 4: Execute Job Script
# ============================================================================

echo "[4/5] Executing job script..."
echo "========================================================================"

# Check if tool-specific container is needed
if [ -n "${TOOL_CONTAINER_IMAGE}" ]; then
    echo "Tool-specific container requested: ${TOOL_CONTAINER_IMAGE}"
    echo "Running in Docker-in-Docker mode..."

    # Verify Docker is available
    if ! command -v docker &> /dev/null; then
        echo "ERROR: Docker not found but TOOL_CONTAINER_IMAGE is set"
        exit 1
    fi

    # Pull tool container
    echo "Pulling tool container..."
    docker pull "${TOOL_CONTAINER_IMAGE}" || {
        echo "[WARN] Failed to pull image, trying cached version..."
    }

    # Run in tool container with full directory structure mounted
    # Mount the entire /galaxy_execution tree
    docker run --rm -i \
        -v "$EXECUTION_ROOT:$EXECUTION_ROOT:rw" \
        -e GALAXY_EXECUTION_ROOT="$EXECUTION_ROOT" \
        -e GALAXY_JOB_DIR="$JOB_DIR" \
        -e GALAXY_WORK_DIR="$WORK_DIR" \
        -e GALAXY_INPUT_DIR="$INPUT_DIR" \
        -e GALAXY_OUTPUT_DIR="$OUTPUT_DIR" \
        -e GALAXY_CONFIG_DIR="$CONFIG_DIR" \
        -e GALAXY_DATASETS_ROOT="$DATASETS_ROOT" \
        -w "$WORK_DIR" \
        "${TOOL_CONTAINER_IMAGE}" \
        bash < "${SCRIPT_FILE}"

    EXIT_CODE=$?
else
    echo "Direct execution mode (no tool-specific container)"

    # Execute directly in fetch-and-run container
    bash "${SCRIPT_FILE}"
    EXIT_CODE=$?
fi

echo "========================================================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "[OK] Job script completed successfully"
else
    echo "[ERROR] Job script failed with exit code ${EXIT_CODE}"
    exit $EXIT_CODE
fi
echo ""

# ============================================================================
# Step 5: Upload Results to S3
# ============================================================================

echo "[5/5] Uploading results to S3..."

# Upload outputs
OUTPUT_S3_PREFIX="s3://${S3_BUCKET}/jobs/${JOB_ID}/outputs/"
if [ -n "$(find ${OUTPUT_DIR} -type f 2>/dev/null)" ]; then
    echo "  Uploading output files..."
    aws s3 sync "${OUTPUT_DIR}/" "${OUTPUT_S3_PREFIX}" --region "${AWS_REGION}" --quiet
    OUTPUT_COUNT=$(find ${OUTPUT_DIR} -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] Uploaded $OUTPUT_COUNT output file(s)"
else
    echo "  [WARN] No output files found"
fi

# Upload metadata (if any generated)
METADATA_S3_PREFIX="s3://${S3_BUCKET}/jobs/${JOB_ID}/metadata/"
if [ -n "$(find ${METADATA_DIR} -type f 2>/dev/null)" ]; then
    echo "  Uploading metadata..."
    aws s3 sync "${METADATA_DIR}/" "${METADATA_S3_PREFIX}" --region "${AWS_REGION}" --quiet
    echo "  [OK] Metadata uploaded"
fi

echo "[OK] Upload complete"
echo ""

# ============================================================================
# Cleanup (optional)
# ============================================================================

echo "Cleaning up temporary files..."
rm -rf "$TMP_DOWNLOAD" 2>/dev/null || true
echo "[OK] Cleanup complete"
echo ""

# ============================================================================
# Success
# ============================================================================

echo "========================================================================"
echo "Galaxy Universal Cloud Executor - Job Complete"
echo "========================================================================"
echo "Job ID: ${JOB_ID}"
echo "Status: SUCCESS"
echo "Output location: ${OUTPUT_S3_PREFIX}"
echo "========================================================================"

exit 0
