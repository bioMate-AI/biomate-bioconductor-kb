#!/bin/bash
# Chai-1 entrypoint script

set -e

case "$1" in
    predict|--predict|fold)
        shift
        exec python -m chai_lab.main "$@"
        ;;
    --help|-h|"")
        echo "Chai-1: Multi-Modal Biomolecular Structure Prediction"
        echo ""
        echo "Usage:"
        echo "  docker run --gpus all biomate/chai1 predict --fasta input.fasta --output output/"
        echo ""
        echo "Commands:"
        echo "  predict   Predict structure from sequence"
        echo "  fold      Alias for predict"
        echo ""
        echo "Requirements:"
        echo "  - NVIDIA GPU with 24GB+ VRAM"
        echo "  - Mount output directory: -v ./output:/workspace"
        echo ""
        echo "Example:"
        echo "  docker run --gpus all -v ./data:/workspace biomate/chai1 predict \\"
        echo "    --fasta /workspace/protein.fasta \\"
        echo "    --output /workspace/output"
        ;;
    *)
        exec "$@"
        ;;
esac
