#!/bin/bash
# Build and push AI tool Docker images to ECR
# Supports: x86_64 (linux/amd64) only
#
# Usage:
#   ./build-ecr.sh                          # build all tools
#   ./build-ecr.sh protrek state profam     # build specific tools
#   ./build-ecr.sh --nextflow-only syncraft # build only :nextflow wrapper for syncraft
#
# Build context: Run from REPO ROOT (not from this directory)
#   cd /home/yzhang/biomate
#   bash backend/docker/biomate-ai-tools/build-ecr.sh

set -e

ECR_REGISTRY="399683337364.dkr.ecr.us-west-2.amazonaws.com"
AWS_REGION="us-west-2"
DOCKER_DIR="backend/docker/biomate-ai-tools"
PLATFORM="linux/amd64"

# ---- Parse arguments ----
NEXTFLOW_ONLY=false
TOOLS_TO_BUILD=()

for arg in "$@"; do
    case "$arg" in
        --nextflow-only) NEXTFLOW_ONLY=true ;;
        *) TOOLS_TO_BUILD+=("$arg") ;;
    esac
done

# Default: build all tools that have both Dockerfile and Dockerfile.nextflow
ALL_TOOLS_WITH_DOCKERFILE=(protrek state profam scfv-pmpnn)
ALL_TOOLS_NEXTFLOW_ONLY=(syncraft drugclip)

if [ ${#TOOLS_TO_BUILD[@]} -eq 0 ]; then
    if [ "$NEXTFLOW_ONLY" = true ]; then
        TOOLS_TO_BUILD=("${ALL_TOOLS_NEXTFLOW_ONLY[@]}")
    else
        TOOLS_TO_BUILD=("${ALL_TOOLS_WITH_DOCKERFILE[@]}" "${ALL_TOOLS_NEXTFLOW_ONLY[@]}")
    fi
fi

log_info() { echo "[$(date +'%H:%M:%S')] INFO: $1"; }
log_error() { echo "[$(date +'%H:%M:%S')] ERROR: $1" >&2; }
log_ok() { echo "[$(date +'%H:%M:%S')] OK: $1"; }

# ---- ECR Login ----
log_info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_REGISTRY"
log_ok "ECR login successful"

build_latest() {
    local tool=$1
    local dockerfile="$DOCKER_DIR/$tool/Dockerfile"
    local image="biomate/ai-tools/$tool"
    local ecr_image="$ECR_REGISTRY/$image"

    if [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile not found: $dockerfile"
        return 1
    fi

    log_info "Building $tool:latest from $dockerfile"
    docker build \
        --platform "$PLATFORM" \
        --no-cache \
        -t "$image:latest" \
        -f "$dockerfile" \
        .

    log_info "Pushing $tool:latest to ECR"
    docker tag "$image:latest" "$ecr_image:latest"
    docker push "$ecr_image:latest"
    log_ok "$ecr_image:latest pushed"
}

build_nextflow() {
    local tool=$1
    local dockerfile="$DOCKER_DIR/$tool/Dockerfile.nextflow"
    local image="biomate/ai-tools/$tool"
    local ecr_image="$ECR_REGISTRY/$image"

    if [ ! -f "$dockerfile" ]; then
        log_error "Dockerfile.nextflow not found: $dockerfile"
        return 1
    fi

    log_info "Building $tool:nextflow wrapper"
    docker build \
        --platform "$PLATFORM" \
        --no-cache \
        -t "$image:nextflow" \
        -f "$dockerfile" \
        .

    log_info "Pushing $tool:nextflow to ECR"
    docker tag "$image:nextflow" "$ecr_image:nextflow"
    docker push "$ecr_image:nextflow"
    log_ok "$ecr_image:nextflow pushed"
}

# ---- Build each tool ----
for tool in "${TOOLS_TO_BUILD[@]}"; do
    echo ""
    echo "=========================================="
    echo "Tool: $tool"
    echo "=========================================="

    has_dockerfile=false
    has_nextflow=false

    [ -f "$DOCKER_DIR/$tool/Dockerfile" ] && has_dockerfile=true
    [ -f "$DOCKER_DIR/$tool/Dockerfile.nextflow" ] && has_nextflow=true

    if [ "$NEXTFLOW_ONLY" = true ]; then
        if [ "$has_nextflow" = true ]; then
            build_nextflow "$tool"
        else
            log_error "$tool: Dockerfile.nextflow not found, skipping"
        fi
    else
        if [ "$has_dockerfile" = true ]; then
            build_latest "$tool"
        else
            log_info "$tool: No Dockerfile (will use existing :latest for nextflow wrapper)"
        fi

        if [ "$has_nextflow" = true ]; then
            build_nextflow "$tool"
        else
            log_error "$tool: Dockerfile.nextflow not found"
        fi
    fi
done

# ---- Summary ----
echo ""
echo "=========================================="
echo "Build Complete"
echo "=========================================="
echo "Tools built: ${TOOLS_TO_BUILD[*]}"
echo ""
echo "Verify in ECR:"
for tool in "${TOOLS_TO_BUILD[@]}"; do
    echo "  aws ecr describe-images --repository-name biomate/ai-tools/$tool --region $AWS_REGION --query 'imageDetails[*].[imageTags[0],imagePushedAt]' --output table"
done
