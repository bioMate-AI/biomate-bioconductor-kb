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

# CRITICAL: For Docker-in-Docker file sharing:
# 1. This container (fetch-and-run) writes files to /host-tmp/galaxy_execution_${JOB_ID}/
#    (which maps to host /tmp/galaxy_execution_${JOB_ID}/)
# 2. Tool containers mount host /tmp/galaxy_execution_${JOB_ID}/ → /galaxy_execution/
#    (so tool sees files at /galaxy_execution/, matching path_rewriter expectations)

# Paths in THIS container (fetch-and-run) - write via /host-tmp mount
HOST_EXECUTION_ROOT="/host-tmp/galaxy_execution_${JOB_ID}"
HOST_JOB_DIR="$HOST_EXECUTION_ROOT/job"
HOST_WORK_DIR="$HOST_JOB_DIR/working"
HOST_INPUT_DIR="$HOST_JOB_DIR/inputs"
HOST_OUTPUT_DIR="$HOST_JOB_DIR/outputs"
HOST_CONFIG_DIR="$HOST_JOB_DIR/configs"
HOST_METADATA_DIR="$HOST_JOB_DIR/metadata"
HOST_DATASETS_ROOT="$HOST_EXECUTION_ROOT/datasets"
HOST_OBJECTS_DIR="$HOST_DATASETS_ROOT/objects"

# Paths on EC2 host (for docker -v mounts)
CONTAINER_HOST_ROOT="/tmp/galaxy_execution_${JOB_ID}"

# Paths inside tool containers (standard, matches universal_path_rewriter)
CONTAINER_EXECUTION_ROOT="/galaxy_execution"
CONTAINER_JOB_DIR="$CONTAINER_EXECUTION_ROOT/job"
CONTAINER_WORK_DIR="$CONTAINER_JOB_DIR/working"
CONTAINER_INPUT_DIR="$CONTAINER_JOB_DIR/inputs"
CONTAINER_OUTPUT_DIR="$CONTAINER_JOB_DIR/outputs"
CONTAINER_CONFIG_DIR="$CONTAINER_JOB_DIR/configs"
CONTAINER_METADATA_DIR="$CONTAINER_JOB_DIR/metadata"
CONTAINER_DATASETS_ROOT="$CONTAINER_EXECUTION_ROOT/datasets"
CONTAINER_OBJECTS_DIR="$CONTAINER_DATASETS_ROOT/objects"

# Working variables point to host paths (where we actually write files)
EXECUTION_ROOT="$HOST_EXECUTION_ROOT"
JOB_DIR="$HOST_JOB_DIR"
WORK_DIR="$HOST_WORK_DIR"
INPUT_DIR="$HOST_INPUT_DIR"
OUTPUT_DIR="$HOST_OUTPUT_DIR"
CONFIG_DIR="$HOST_CONFIG_DIR"
METADATA_DIR="$HOST_METADATA_DIR"
DATASETS_ROOT="$HOST_DATASETS_ROOT"
OBJECTS_DIR="$HOST_OBJECTS_DIR"

# Job script location
SCRIPT_FILE="$HOST_JOB_DIR/job_script.sh"

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
    cp -r "$TMP_DOWNLOAD/inputs/"* "$INPUT_DIR/" 2>/dev/null || true
    INPUT_COUNT=$(find "$INPUT_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] $INPUT_COUNT input file(s)"
fi

# working/* → WORK_DIR
if [ -d "$TMP_DOWNLOAD/working" ]; then
    echo "  Processing working files..."
    cp -r "$TMP_DOWNLOAD/working/"* "$WORK_DIR/" 2>/dev/null || true
    WORKING_COUNT=$(find "$WORK_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] $WORKING_COUNT working file(s)"
fi

# configs/* → CONFIG_DIR
if [ -d "$TMP_DOWNLOAD/configs" ]; then
    echo "  Processing config files..."
    echo "  Source: $TMP_DOWNLOAD/configs/"
    echo "  Target: $CONFIG_DIR/"
    ls -la "$TMP_DOWNLOAD/configs/" || echo "  Cannot list source!"
    cp -r "$TMP_DOWNLOAD/configs/"* "$CONFIG_DIR/" 2>&1 || echo "  cp failed!"
    echo "  Result in target:"
    ls -la "$CONFIG_DIR/" || echo "  Cannot list target!"
    CONFIG_COUNT=$(find "$CONFIG_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] $CONFIG_COUNT config file(s)"
fi

# metadata/* → METADATA_DIR
if [ -d "$TMP_DOWNLOAD/metadata" ]; then
    echo "  Processing metadata files..."
    cp -r "$TMP_DOWNLOAD/metadata/"* "$METADATA_DIR/" 2>/dev/null || true
fi

# datasets/objects/* → OBJECTS_DIR (if any pre-staged datasets)
if [ -d "$TMP_DOWNLOAD/datasets/objects" ]; then
    echo "  Processing dataset objects..."
    cp -r "$TMP_DOWNLOAD/datasets/objects/"* "$OBJECTS_DIR/" 2>/dev/null || true
fi

# tools/* → Create Galaxy-compatible shed_tools structure
if [ -d "$TMP_DOWNLOAD/tools" ]; then
    echo "  Processing tool scripts..."
    # Create shed_tools directory in container
    # Map to /galaxy/shed_tools to match Galaxy's expected path
    SHED_TOOLS_DIR="/host-tmp/galaxy_shed_tools"
    mkdir -p "$SHED_TOOLS_DIR"

    # Copy all tool files preserving structure
    # tools/toolshed.g2.bx.psu.edu/repos/... → /galaxy/shed_tools/toolshed.g2.bx.psu.edu/repos/...
    cp -r "$TMP_DOWNLOAD/tools/"* "$SHED_TOOLS_DIR/" 2>/dev/null || true
    TOOL_COUNT=$(find "$SHED_TOOLS_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] $TOOL_COUNT tool file(s) downloaded to $SHED_TOOLS_DIR"
fi

# Cleanup temp download
rm -rf "$TMP_DOWNLOAD"

echo "[OK] All job files downloaded and organized"
echo ""

# ============================================================================
# Step 3: Set Up Execution Environment
# ============================================================================

echo "[3/5] Setting up execution environment..."

# Export environment variables (used for non-containerized execution)
# For containerized execution, these are overridden by docker run -e flags
export GALAXY_EXECUTION_ROOT="$HOST_EXECUTION_ROOT"
export GALAXY_JOB_DIR="$HOST_JOB_DIR"
export GALAXY_WORK_DIR="$HOST_WORK_DIR"
export GALAXY_INPUT_DIR="$HOST_INPUT_DIR"
export GALAXY_OUTPUT_DIR="$HOST_OUTPUT_DIR"
export GALAXY_CONFIG_DIR="$HOST_CONFIG_DIR"
export GALAXY_DATASETS_ROOT="$HOST_DATASETS_ROOT"

# Debug: Show environment
echo "  Environment variables set (for this container):"
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
    if ! docker pull "${TOOL_CONTAINER_IMAGE}"; then
        echo "[WARN] Failed to pull image: ${TOOL_CONTAINER_IMAGE}"

        # Check if image exists locally
        if ! docker image inspect "${TOOL_CONTAINER_IMAGE}" >/dev/null 2>&1; then
            echo "[ERROR] Image not found locally either"
            echo "[UNIVERSAL-FALLBACK] Tool-specific image unavailable"
            echo "[UNIVERSAL-FALLBACK] Will execute in fetch-and-run container (has Python+R+Perl+Java)"
            # Clear image to use direct execution in enhanced fetch-and-run container
            TOOL_CONTAINER_IMAGE=""
        else
            echo "[OK] Using cached local image"
        fi
    fi
fi

# Run in tool container if image is available
if [ -n "${TOOL_CONTAINER_IMAGE}" ]; then
    # Run in tool container with full directory structure mounted
    # Mount the entire /galaxy_execution tree

    # Debug: verify files exist before mounting
    echo "Pre-mount verification:"
    echo "  Config dir contents:"
    ls -la "$CONFIG_DIR" 2>&1 || echo "  Config dir does not exist!"
    echo "  Execution root contents:"
    find "$EXECUTION_ROOT" -type f 2>&1 | head -20

    # Mount from EC2 host /tmp/galaxy_execution_{JOB_ID} to tool container /galaxy_execution
    # This remapping ensures tool containers see files at standard /galaxy_execution paths
    # CRITICAL: Also mount shed_tools so tool scripts are accessible
    docker run --rm -i \
        -v "${CONTAINER_HOST_ROOT}/job:${CONTAINER_JOB_DIR}:rw" \
        -v "${CONTAINER_HOST_ROOT}/datasets:${CONTAINER_DATASETS_ROOT}:rw" \
        -v "/tmp/galaxy_shed_tools:/galaxy/shed_tools:ro" \
        -e GALAXY_EXECUTION_ROOT="$CONTAINER_EXECUTION_ROOT" \
        -e GALAXY_JOB_DIR="$CONTAINER_JOB_DIR" \
        -e GALAXY_WORK_DIR="$CONTAINER_WORK_DIR" \
        -e GALAXY_INPUT_DIR="$CONTAINER_INPUT_DIR" \
        -e GALAXY_OUTPUT_DIR="$CONTAINER_OUTPUT_DIR" \
        -e GALAXY_CONFIG_DIR="$CONTAINER_CONFIG_DIR" \
        -e GALAXY_DATASETS_ROOT="$CONTAINER_DATASETS_ROOT" \
        -w "$CONTAINER_WORK_DIR" \
        "${TOOL_CONTAINER_IMAGE}" \
        sh -c "
            echo 'Container started - verifying mounts:'
            echo 'Job dir:' && ls -la \$GALAXY_JOB_DIR
            echo 'Config dir exists:' && test -d \$GALAXY_CONFIG_DIR && echo 'YES' || echo 'NO'
            echo 'Config contents:' && ls -la \$GALAXY_CONFIG_DIR 2>&1 || echo 'Not accessible'
            echo 'Shed tools:' && ls /galaxy/shed_tools 2>&1 | head -5 || echo 'Not accessible'
            bash
        " < "${SCRIPT_FILE}"

    EXIT_CODE=$?
else
    echo "Direct execution mode (no tool-specific container)"
    echo "Using enhanced fetch-and-run container with Python+Perl+common tools"

    # Execute directly in fetch-and-run container, capturing output
    bash "${SCRIPT_FILE}" 2>&1 | tee "${SCRIPT_FILE}.log"
    EXIT_CODE=${PIPESTATUS[0]}

    # DYNAMIC INSTALLATION: If job failed, analyze error and try to install missing runtime
    if [ $EXIT_CODE -ne 0 ]; then
        echo ""
        echo "[WARN] Job failed with exit code $EXIT_CODE"
        echo "[DYNAMIC-INSTALL] Analyzing error for missing runtimes..."

        # Read error log for analysis
        ERROR_LOG=$(cat "${SCRIPT_FILE}.log" 2>/dev/null || echo "")

        INSTALLED_SOMETHING=false

        # Check for common missing command patterns
        # Note: R should be pre-installed in the base image now, so this is just a fallback
        if echo "$ERROR_LOG" | grep -qi "command not found.*Rscript\|Rscript.*not found\|command not found.*R\b"; then
            echo "[DYNAMIC-INSTALL] Detected missing: R/Rscript (unexpected, should be pre-installed)"
            echo "[DYNAMIC-INSTALL] Installing R from EPEL as fallback..."
            if yum install -y R libxml2-devel libcurl-devel openssl-devel 2>&1 | tee /tmp/r_install.log; then
                echo "[DYNAMIC-INSTALL] ✅ R installed successfully"
                R --version
                # Also install BiocManager for package installation
                Rscript -e "install.packages('BiocManager', repos='https://cloud.r-project.org/')"
                INSTALLED_SOMETHING=true
            else
                echo "[DYNAMIC-INSTALL] ❌ Failed to install R"
                cat /tmp/r_install.log
            fi
        fi

        if echo "$ERROR_LOG" | grep -qi "command not found.*node\|node.*not found"; then
            echo "[DYNAMIC-INSTALL] Detected missing: Node.js"
            echo "[DYNAMIC-INSTALL] Installing Node.js..."
            curl -fsSL https://rpm.nodesource.com/setup_16.x | bash - && \
            yum install -y nodejs && \
            INSTALLED_SOMETHING=true
        fi

        if echo "$ERROR_LOG" | grep -qi "command not found.*ruby\|ruby.*not found"; then
            echo "[DYNAMIC-INSTALL] Detected missing: Ruby"
            echo "[DYNAMIC-INSTALL] Installing Ruby..."
            yum install -y ruby && \
            INSTALLED_SOMETHING=true
        fi

        if echo "$ERROR_LOG" | grep -qi "command not found.*java\b"; then
            echo "[DYNAMIC-INSTALL] Detected missing: Java"
            echo "[DYNAMIC-INSTALL] Installing Java..."
            yum install -y java-1.8.0-openjdk && \
            INSTALLED_SOMETHING=true
        fi

        # If we installed something, retry the job
        if [ "$INSTALLED_SOMETHING" = true ]; then
            echo "[DYNAMIC-INSTALL] Retrying job with newly installed runtime..."

            # Loop to handle cascading R package dependencies
            MAX_R_PACKAGE_RETRIES=5
            R_RETRY_COUNT=0

            while [ $R_RETRY_COUNT -lt $MAX_R_PACKAGE_RETRIES ]; do
                bash "${SCRIPT_FILE}" 2>&1 | tee "${SCRIPT_FILE}.log.retry${R_RETRY_COUNT}"
                EXIT_CODE=${PIPESTATUS[0]}

                if [ $EXIT_CODE -eq 0 ]; then
                    echo "[DYNAMIC-INSTALL] ✅ Job succeeded!"
                    break
                fi

                # Check if it's missing R packages
                # Check both first run (.log) and retry logs (.log.retry*)
                if [ $R_RETRY_COUNT -eq 0 ]; then
                    RETRY_LOG=$(cat "${SCRIPT_FILE}.log" 2>/dev/null || echo "")
                else
                    RETRY_LOG=$(cat "${SCRIPT_FILE}.log.retry$((R_RETRY_COUNT - 1))" 2>/dev/null || echo "")
                fi
                if echo "$RETRY_LOG" | grep -qi "there is no package called\|Error in library"; then
                    echo "[DYNAMIC-INSTALL] Detected missing R packages (attempt $((R_RETRY_COUNT + 1))/$MAX_R_PACKAGE_RETRIES)"

                    # Extract package names from error messages like: there is no package called 'getopt'
                    MISSING_PACKAGES=$(echo "$RETRY_LOG" | grep -oP "(?<=there is no package called ')[^']+(?=')" | sort -u)

                    if [ -n "$MISSING_PACKAGES" ]; then
                        echo "[DYNAMIC-INSTALL] Missing R packages: $MISSING_PACKAGES"
                        echo "[DYNAMIC-INSTALL] Installing R packages..."

                        # First ensure BiocManager is installed
                        if ! Rscript -e "library('BiocManager')" 2>/dev/null; then
                            echo "[DYNAMIC-INSTALL] BiocManager not found, installing..."
                            Rscript -e "install.packages('BiocManager', repos='https://cloud.r-project.org/')" 2>&1 | tail -10
                        fi

                        # Install each missing package using BiocManager (smart CRAN/Bioconductor detection)
                        ALL_INSTALLED=true
                        for pkg in $MISSING_PACKAGES; do
                            echo "[DYNAMIC-INSTALL] Installing R package: $pkg"

                            # Use BiocManager::install() which automatically handles both CRAN and Bioconductor packages
                            if ! Rscript -e "BiocManager::install('$pkg', update=FALSE, ask=FALSE)" 2>&1 | tee /tmp/r_pkg_install_${pkg}.log | tail -15; then
                                echo "[WARN] BiocManager installation of $pkg may have issues"
                                echo "[DYNAMIC-INSTALL] Trying fallback with install.packages()..."
                                Rscript -e "install.packages('$pkg', repos='https://cloud.r-project.org/', dependencies=TRUE)" 2>&1 | tail -10
                            fi

                            # Quick check if package is now available
                            if Rscript -e "library('$pkg')" 2>/dev/null; then
                                echo "[OK] Package $pkg installed successfully"
                            else
                                echo "[WARN] Package $pkg may not be fully installed"
                                ALL_INSTALLED=false
                            fi
                        done

                        R_RETRY_COUNT=$((R_RETRY_COUNT + 1))
                        echo "[DYNAMIC-INSTALL] R packages installation round $R_RETRY_COUNT complete, retrying job..."
                    else
                        echo "[DYNAMIC-INSTALL] Could not extract package names, stopping retries"
                        break
                    fi
                else
                    echo "[DYNAMIC-INSTALL] Job failed but not due to missing R packages"
                    break
                fi
            done

            if [ $R_RETRY_COUNT -ge $MAX_R_PACKAGE_RETRIES ] && [ $EXIT_CODE -ne 0 ]; then
                echo "[DYNAMIC-INSTALL] ❌ Max retries reached, job still failing"
            fi
        else
            echo "[DYNAMIC-INSTALL] No obvious missing runtime detected"
            echo "[DYNAMIC-INSTALL] Job may require specialized tool container"
        fi
    fi
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

# Upload outputs from outputs/ directory
OUTPUT_S3_PREFIX="s3://${S3_BUCKET}/jobs/${JOB_ID}/outputs/"
if [ -n "$(find ${OUTPUT_DIR} -type f 2>/dev/null)" ]; then
    echo "  Uploading output files from outputs/..."
    aws s3 sync "${OUTPUT_DIR}/" "${OUTPUT_S3_PREFIX}" --region "${AWS_REGION}" --quiet
    OUTPUT_COUNT=$(find ${OUTPUT_DIR} -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] Uploaded $OUTPUT_COUNT output file(s)"
else
    echo "  [INFO] No files in outputs/ directory"
fi

# Upload datasets (Galaxy's object store outputs)
DATASETS_S3_PREFIX="s3://${S3_BUCKET}/jobs/${JOB_ID}/datasets/"
if [ -n "$(find ${DATASETS_ROOT} -type f 2>/dev/null)" ]; then
    echo "  Uploading dataset files..."
    aws s3 sync "${DATASETS_ROOT}/" "${DATASETS_S3_PREFIX}" --region "${AWS_REGION}" --quiet
    DATASET_COUNT=$(find ${DATASETS_ROOT} -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  [OK] Uploaded $DATASET_COUNT dataset file(s)"
else
    echo "  [INFO] No dataset files found"
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
