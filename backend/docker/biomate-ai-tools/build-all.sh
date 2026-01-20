#!/bin/bash
# Build script for Biomate AI Tools Docker images
# Supports multi-architecture builds (AMD64 + ARM64)

set -e

REGISTRY="${DOCKER_REGISTRY:-biomate}"
VERSION="${VERSION:-latest}"
PLATFORMS="${PLATFORMS:-linux/amd64}"  # Add linux/arm64 when ready

echo "========================================"
echo "Biomate AI Tools Docker Build"
echo "========================================"
echo "Registry: $REGISTRY"
echo "Version: $VERSION"
echo "Platforms: $PLATFORMS"
echo ""

# Tools to build (ordered by resource requirements - light first)
TOOLS=(
    "syncraft:CPU only, uses Gemini API"
    "state:CPU or GPU, single-cell perturbation"
    "drugclip:CPU or GPU, virtual screening"
    "protrek:CPU or 8GB GPU, protein search"
    "profam:CPU or 8GB GPU, fitness prediction"
    "scfv-pmpnn:16GB GPU, antibody design"
    "boltz:16-40GB GPU, structure prediction"
    "chai1:24-80GB GPU, multi-modal structure"
)

build_tool() {
    local tool=$1
    local description=$2

    echo ""
    echo "----------------------------------------"
    echo "Building: $tool"
    echo "Description: $description"
    echo "----------------------------------------"

    if [ -d "$tool" ] && [ -f "$tool/Dockerfile" ]; then
        docker buildx build \
            --platform $PLATFORMS \
            -t $REGISTRY/$tool:$VERSION \
            $tool/

        echo "✓ Built $REGISTRY/$tool:$VERSION"
    else
        echo "⚠ Skipping $tool - Dockerfile not found"
    fi
}

# Build each tool
for tool_info in "${TOOLS[@]}"; do
    IFS=':' read -r tool description <<< "$tool_info"
    build_tool "$tool" "$description"
done

echo ""
echo "========================================"
echo "Build Complete"
echo "========================================"
echo ""
echo "To push images:"
echo "  docker push $REGISTRY/<tool>:$VERSION"
echo ""
echo "To enable multi-arch builds:"
echo "  export PLATFORMS='linux/amd64,linux/arm64'"
echo "  docker buildx create --use --name multiarch"
echo "  ./build-all.sh"
