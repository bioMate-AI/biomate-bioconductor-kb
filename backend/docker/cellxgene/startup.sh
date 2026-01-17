#!/bin/bash
# Galaxy Interactive Tool startup for CellxGene

# Find the h5ad file to visualize
H5AD_FILE=""

# Check common locations
if [ -f "/import/dataset.h5ad" ]; then
    H5AD_FILE="/import/dataset.h5ad"
elif [ -f "/import/data.h5ad" ]; then
    H5AD_FILE="/import/data.h5ad"
elif [ -n "$(find /import -name '*.h5ad' -type f 2>/dev/null | head -1)" ]; then
    H5AD_FILE=$(find /import -name '*.h5ad' -type f 2>/dev/null | head -1)
fi

if [ -z "$H5AD_FILE" ]; then
    echo "ERROR: No .h5ad file found in /import"
    echo "Please ensure your AnnData file is mounted to /import"
    exit 1
fi

echo "Starting CellxGene with: $H5AD_FILE"

# Start cellxgene
exec cellxgene launch "$H5AD_FILE" \
    --host 0.0.0.0 \
    --port ${CELLXGENE_PORT:-5005} \
    --disable-annotations \
    --open-browser false
