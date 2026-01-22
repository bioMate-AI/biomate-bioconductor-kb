#!/bin/bash
# ProTrek entrypoint script

set -e

case "$1" in
    search|--search)
        shift
        exec python /opt/protrek/demo/search.py "$@"
        ;;
    embed|--embed)
        shift
        exec python /opt/protrek/demo/embed.py "$@"
        ;;
    --help|-h|"")
        echo "ProTrek: Protein Sequence-Structure-Function Search"
        echo ""
        echo "Usage:"
        echo "  docker run biomate/protrek search --query 'kinase' --type text"
        echo "  docker run biomate/protrek embed --input proteins.fasta"
        echo ""
        echo "Commands:"
        echo "  search    Search proteins by text, sequence, or structure"
        echo "  embed     Generate embeddings for proteins"
        echo ""
        echo "Mount models:"
        echo "  -v /path/to/protrek:/models/protrek"
        echo ""
        echo "Web interface available at: https://search-protrek.com"
        ;;
    *)
        exec "$@"
        ;;
esac
