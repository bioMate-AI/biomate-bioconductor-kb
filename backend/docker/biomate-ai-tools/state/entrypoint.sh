#!/bin/bash
# STATE entrypoint script

set -e

case "$1" in
    tx|transition)
        shift
        exec state tx "$@"
        ;;
    emb|embedding)
        shift
        exec state emb "$@"
        ;;
    --help|-h|"")
        echo "STATE: Virtual Cell Model for Perturbation Response"
        echo ""
        echo "Usage:"
        echo "  docker run biomate/state tx infer --help"
        echo "  docker run biomate/state emb transform --help"
        echo ""
        echo "Commands:"
        echo "  tx        Transition model (perturbation prediction)"
        echo "  emb       Embedding model (cell state encoding)"
        echo ""
        echo "Mount data:"
        echo "  -v /path/to/data:/workspace"
        echo "  -v /path/to/models:/models"
        echo ""
        echo "Example:"
        echo "  docker run -v ./data:/workspace biomate/state tx infer \\"
        echo "    --adata /workspace/perturb_data.h5ad \\"
        echo "    --model-dir /models/state \\"
        echo "    --output /workspace/predicted.h5ad"
        ;;
    *)
        exec "$@"
        ;;
esac
