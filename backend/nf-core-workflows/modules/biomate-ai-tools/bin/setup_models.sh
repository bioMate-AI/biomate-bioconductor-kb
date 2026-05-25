#!/bin/bash
# Setup script for Biomate AI Tools model weights
#
# Usage:
#   ./setup_models.sh                    # Download all models to default location
#   ./setup_models.sh /path/to/models    # Download to specific location
#   ./setup_models.sh --s3               # Upload to S3 after download
#
# Models downloaded:
#   - profam:  ~1.5 GB (HuggingFace: judewells/ProFam-1)
#   - state:   ~28 GB  (HuggingFace: arcinstitute/SE-600M)
#   - boltz:   ~12 GB  (auto-downloads on first run)
#   - chai1:   ~15 GB  (auto-downloads on first run)

set -e

MODELS_DIR="${1:-/opt/biomate/models}"
S3_BUCKET="s3://biomate-models"
UPLOAD_S3=false

if [ "$1" == "--s3" ] || [ "$2" == "--s3" ]; then
    UPLOAD_S3=true
fi

echo "=============================================="
echo "Biomate AI Tools - Model Setup"
echo "=============================================="
echo "Models directory: $MODELS_DIR"
echo ""

mkdir -p "$MODELS_DIR"

# Check for huggingface-cli
if ! command -v huggingface-cli &> /dev/null; then
    echo "Installing huggingface_hub..."
    pip install huggingface_hub
fi

# Download ProFam model
download_profam() {
    echo "Downloading ProFam-1 (~1.5 GB)..."
    if [ -d "$MODELS_DIR/profam" ] && [ -f "$MODELS_DIR/profam/pytorch_model.bin" ]; then
        echo "  ProFam already exists, skipping"
        return
    fi
    huggingface-cli download judewells/ProFam-1 --local-dir "$MODELS_DIR/profam"
    echo "  ProFam downloaded successfully"
}

# Download STATE model
download_state() {
    echo "Downloading STATE SE-600M (~28 GB)..."
    if [ -d "$MODELS_DIR/state" ] && [ -f "$MODELS_DIR/state/model.safetensors" ]; then
        echo "  STATE already exists, skipping"
        return
    fi
    huggingface-cli download arcinstitute/SE-600M --local-dir "$MODELS_DIR/state"
    echo "  STATE downloaded successfully"
}

# Note about auto-downloading models
echo_auto_models() {
    echo ""
    echo "Note: The following models auto-download on first run:"
    echo "  - Boltz-2:  ~12 GB (downloads to ~/.cache/boltz)"
    echo "  - Chai-1:   ~15 GB (downloads to ~/.cache/chai)"
    echo ""
    echo "To pre-download, run the container once:"
    echo "  docker run --rm -v \$HOME/.cache:/root/.cache biomate/boltz:latest predict --help"
    echo "  docker run --rm -v \$HOME/.cache:/root/.cache biomate/chai1:latest predict --help"
}

# Upload to S3 (optional)
upload_to_s3() {
    if [ "$UPLOAD_S3" = true ]; then
        echo ""
        echo "Uploading to S3: $S3_BUCKET"
        aws s3 sync "$MODELS_DIR" "$S3_BUCKET" --exclude "*.git/*"
        echo "S3 upload complete"
    fi
}

# Main
download_profam
download_state
echo_auto_models
upload_to_s3

echo ""
echo "=============================================="
echo "Setup Complete!"
echo "=============================================="
echo ""
echo "Models location: $MODELS_DIR"
echo ""
echo "To use in Nextflow:"
echo "  nextflow run pipeline.nf --models_dir $MODELS_DIR"
echo ""
echo "To use with Docker:"
echo "  docker run -v $MODELS_DIR:/models biomate/state:latest ..."
echo ""

# List downloaded models
echo "Downloaded models:"
du -sh "$MODELS_DIR"/* 2>/dev/null || echo "  (none yet)"
