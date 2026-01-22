#!/bin/bash
# scFv-pMPNN entrypoint script

set -e

case "$1" in
    design|--design)
        shift
        exec python /opt/scfv-pmpnn/run_design.py "$@"
        ;;
    predict|--predict)
        shift
        exec python /opt/scfv-pmpnn/run_predict.py "$@"
        ;;
    --help|-h|"")
        echo "scFv-pMPNN: Single-chain Fv Antibody Design"
        echo ""
        echo "Usage:"
        echo "  docker run --gpus all biomate/scfv-pmpnn design --input antibody.pdb"
        echo ""
        echo "Commands:"
        echo "  design    Design antibody sequences using ProteinMPNN"
        echo "  predict   Predict structure using AlphaFold2"
        echo ""
        echo "Requirements:"
        echo "  - NVIDIA GPU with 16GB+ VRAM"
        echo "  - Mount model weights: -v /path/to/models:/models"
        echo ""
        echo "Example:"
        echo "  docker run --gpus all -v ./data:/workspace biomate/scfv-pmpnn design \\"
        echo "    --input /workspace/antibody.pdb \\"
        echo "    --output /workspace/designed_sequences.fasta"
        ;;
    *)
        exec "$@"
        ;;
esac
