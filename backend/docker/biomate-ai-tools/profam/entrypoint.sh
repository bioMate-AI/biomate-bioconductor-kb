#!/bin/bash
# ProFam entrypoint script

set -e

# Check for model weights
if [ ! -d "/models/profam/checkpoints" ] && [ ! -f "/models/profam/.hydra/config.yaml" ]; then
    echo "WARNING: ProFam model weights not found in /models/profam"
    echo "Mount your model directory: -v /path/to/profam:/models/profam"
    echo ""
fi

# Route to appropriate script based on first argument
case "$1" in
    score|--score)
        shift
        exec python /opt/profam/scripts/score_sequences.py "$@"
        ;;
    generate|--generate)
        shift
        exec python /opt/profam/scripts/generate_sequences.py "$@"
        ;;
    --help|-h|"")
        echo "ProFam-1: Protein Family Language Model"
        echo ""
        echo "Usage:"
        echo "  docker run biomate/profam score --help"
        echo "  docker run biomate/profam generate --help"
        echo ""
        echo "Commands:"
        echo "  score     Score protein sequences for fitness"
        echo "  generate  Generate new protein sequences"
        echo ""
        echo "Mount models:"
        echo "  -v /path/to/profam:/models/profam"
        echo ""
        echo "Example:"
        echo "  docker run -v ./models:/models -v ./data:/workspace biomate/profam score \\"
        echo "    --checkpoint_dir /models/profam \\"
        echo "    --conditioning_fasta /workspace/family.fasta \\"
        echo "    --candidates_file /workspace/variants.csv \\"
        echo "    --save_dir /workspace/output"
        ;;
    *)
        exec "$@"
        ;;
esac
