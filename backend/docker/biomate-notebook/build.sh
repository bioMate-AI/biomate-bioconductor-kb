#!/bin/bash
# Build BioMate Analysis Notebook Docker image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="biomate/analysis-notebook"
VERSION="${1:-latest}"

echo "Building $IMAGE_NAME:$VERSION..."

docker build \
    -t "$IMAGE_NAME:$VERSION" \
    -t "$IMAGE_NAME:latest" \
    --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    .

echo ""
echo "Build complete: $IMAGE_NAME:$VERSION"
echo ""
echo "To test locally:"
echo "  docker run -p 8888:8888 $IMAGE_NAME:$VERSION"
echo ""
echo "To run a template notebook in batch mode:"
echo "  docker run -v /path/to/input:/import -v /path/to/output:/export \\"
echo "    $IMAGE_NAME:$VERSION \\"
echo "    papermill templates/transcriptomics/deseq2_visualization.ipynb /export/executed.ipynb"
