#!/bin/bash
# Build all BioMate Docker containers
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION="${1:-latest}"

echo "=========================================="
echo "Building BioMate Docker Containers v$VERSION"
echo "=========================================="

# Build order matters for dependencies

# 1. All-in-One Interactive Tools (recommended)
echo ""
echo "[1/3] Building biomate-interactive (all-in-one)..."
docker build -t biomate/interactive:$VERSION \
             -t biomate/interactive:latest \
             ./biomate-interactive

# 2. Analysis Notebook (for batch execution)
echo ""
echo "[2/3] Building biomate-notebook (batch analysis)..."
docker build -t biomate/analysis-notebook:$VERSION \
             -t biomate/analysis-notebook:latest \
             ./biomate-notebook

# 3. Individual tools (optional, if you prefer separate containers)
if [ "$BUILD_INDIVIDUAL" = "true" ]; then
    echo ""
    echo "[3/3] Building individual tool containers..."

    for tool in jupyter-biomate rstudio-biomate cellxgene pavian bam-iobio vcf-iobio; do
        if [ -d "./$tool" ] && [ -f "./$tool/Dockerfile" ]; then
            echo "  Building $tool..."
            docker build -t biomate/$tool:$VERSION \
                         -t biomate/$tool:latest \
                         ./$tool
        fi
    done
fi

echo ""
echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "Images built:"
docker images | grep biomate | head -20
echo ""
echo "Quick start:"
echo "  # All-in-one interactive environment"
echo "  docker run -p 80:80 -v /path/to/data:/import biomate/interactive:latest"
echo ""
echo "  # Batch notebook execution"
echo "  docker run -v /data:/import -v /output:/export biomate/analysis-notebook:latest \\"
echo "    papermill templates/transcriptomics/deseq2_visualization.ipynb /export/results.ipynb"
