#!/usr/bin/env bash
# Download reference datasets for virtual cell GPU workflows
# Run this on the dev EC2 instance to pre-populate /models/ before building Docker image
# Usage: bash scripts/download_virtual_cell_data.sh [--all | --gears | --cpa | --tf]

set -euo pipefail

MODELS_DIR="${MODELS_DIR:-/models}"
DATA_DIR="${DATA_DIR:-/data/virtual_cell_reference}"

mkdir -p "$MODELS_DIR/gears_pretrained"
mkdir -p "$MODELS_DIR/transcriptformer"
mkdir -p "$MODELS_DIR/geneformer"
mkdir -p "$MODELS_DIR/cpa_pretrained"
mkdir -p "$DATA_DIR"

MODE="${1:---all}"

echo "=== BioMate Virtual Cell Data Download ==="
echo "MODELS_DIR: $MODELS_DIR"
echo "DATA_DIR:   $DATA_DIR"
echo ""

# ── Norman 2019 (K562 CRISPRa — primary GEARS training set) ──────────────
download_norman2019() {
    echo "[1/4] Downloading Norman 2019 (K562 CRISPRa, ~111K cells)..."
    NORMAN_DIR="$DATA_DIR/norman2019"
    mkdir -p "$NORMAN_DIR"
    if [ ! -f "$NORMAN_DIR/norman_2019.h5ad" ]; then
        # Figshare DOI: 10.6084/m9.figshare.24688110
        python3 -c "
import urllib.request, os
url = 'https://figshare.com/ndownloader/files/43807544'
dest = '$NORMAN_DIR/norman_2019.h5ad'
print(f'Downloading Norman 2019 from Figshare...')
urllib.request.urlretrieve(url, dest)
print(f'Saved to {dest}')
"
    else
        echo "  Already downloaded: $NORMAN_DIR/norman_2019.h5ad"
    fi
}

# ── Replogle 2022 K562 essential (genome-scale Perturb-seq) ───────────────
download_replogle2022() {
    echo "[2/4] Downloading Replogle 2022 K562 essential (~300K cells)..."
    REPLOGLE_DIR="$DATA_DIR/replogle2022"
    mkdir -p "$REPLOGLE_DIR"
    if [ ! -f "$REPLOGLE_DIR/replogle_2022_k562_essential.h5ad" ]; then
        python3 -c "
import urllib.request, os
# Figshare DOI: 10.6084/m9.figshare.20029387 — K562 essential
url = 'https://figshare.com/ndownloader/files/35775459'
dest = '$REPLOGLE_DIR/replogle_2022_k562_essential.h5ad'
print(f'Downloading Replogle 2022 K562 essential from Figshare...')
urllib.request.urlretrieve(url, dest)
print(f'Saved to {dest}')
"
    else
        echo "  Already downloaded: $REPLOGLE_DIR/replogle_2022_k562_essential.h5ad"
    fi
}

# ── Geneformer V2 model weights ───────────────────────────────────────────
download_geneformer() {
    echo "[3/4] Downloading Geneformer V2 model weights..."
    GENEFORMER_DIR="$MODELS_DIR/geneformer"
    if [ ! -d "$GENEFORMER_DIR/geneformer-12L-30M" ]; then
        python3 -c "
from transformers import AutoTokenizer, AutoModel
import os
cache = '$GENEFORMER_DIR'
os.makedirs(cache, exist_ok=True)
print('Downloading Geneformer V2 104M...')
AutoTokenizer.from_pretrained('ctheodoris/Geneformer', cache_dir=cache)
AutoModel.from_pretrained('ctheodoris/Geneformer', cache_dir=cache)
print('Geneformer weights saved.')
"
    else
        echo "  Already downloaded: $GENEFORMER_DIR"
    fi
}

# ── CZI TranscriptFormer model weights ────────────────────────────────────
download_transcriptformer() {
    echo "[4/4] Downloading CZI TranscriptFormer v0.6.0..."
    TF_DIR="$MODELS_DIR/transcriptformer"
    if [ ! -f "$TF_DIR/config.json" ]; then
        python3 -c "
try:
    import transcriptformer as tf_module
    import os
    os.makedirs('$TF_DIR', exist_ok=True)
    print('Downloading TranscriptFormer v0.6.0...')
    model = tf_module.load('transcriptformer-v0.6.0', cache_dir='$TF_DIR')
    print('TranscriptFormer weights saved to $TF_DIR')
except Exception as e:
    print(f'Error: {e}')
    print('Install first: pip install git+https://github.com/czi-ai/transcriptformer.git')
"
    else
        echo "  Already downloaded: $TF_DIR"
    fi
}

# ── scPerturb benchmark datasets ─────────────────────────────────────────
download_scperturb() {
    echo "[opt] Downloading scPerturb benchmark (Zenodo 7041848)..."
    SCPERT_DIR="$DATA_DIR/scperturb"
    mkdir -p "$SCPERT_DIR"
    if [ ! -f "$SCPERT_DIR/K562_gwps_normalized_bulk_01.h5ad" ]; then
        python3 -c "
import urllib.request, os
# Zenodo 7041848 — K562 GWPS bulk
url = 'https://zenodo.org/record/7041848/files/K562_gwps_normalized_bulk_01.h5ad'
dest = '$SCPERT_DIR/K562_gwps_normalized_bulk_01.h5ad'
print(f'Downloading scPerturb K562 GWPS from Zenodo...')
urllib.request.urlretrieve(url, dest)
print(f'Saved to {dest}')
" || echo "  scPerturb download failed (try manually from scperturb.org)"
    fi
}

case "$MODE" in
    --gears)   download_norman2019; download_replogle2022 ;;
    --tf)      download_transcriptformer ;;
    --geneformer) download_geneformer ;;
    --scperturb) download_scperturb ;;
    --all)
        download_norman2019
        download_replogle2022
        download_geneformer
        download_transcriptformer
        download_scperturb
        ;;
    *)
        echo "Usage: $0 [--all | --gears | --tf | --geneformer | --scperturb]"
        exit 1
        ;;
esac

echo ""
echo "=== Download complete ==="
echo "Models: $MODELS_DIR"
echo "Data:   $DATA_DIR"
echo ""
echo "Next steps:"
echo "  1. Build GPU image: docker buildx build --platform linux/amd64 \\"
echo "       -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/virtual-cell-gpu:1.0 \\"
echo "       --push -f backend/docker/virtual-cell-gpu/Dockerfile ."
echo "  2. Push to ECR: see Dockerfile header for full command"
echo "  3. Test: nextflow run virtual_cell/gears_perturbation_gpu/main.nf \\"
echo "       -profile awsbatch --perturb_genes 'MYC' --cell_line K562"
