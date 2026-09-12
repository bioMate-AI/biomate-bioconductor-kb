#!/usr/bin/env bash
set -euo pipefail
# Run on the same remote host/package as joint training. No whole HDF5 download.
# Arguments: frozen object manifest, paired manifest (for vocabulary union), new output dir.
if [ "$#" -ne 3 ]; then echo 'usage: run_all_source_headers.sh OBJECT_MANIFEST PAIRED_MANIFEST NEW_OUTPUT' >&2; exit 2; fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/preflight_all_source_headers.py" \
  --manifest "$1" --policy "$SCRIPT_DIR/cellxgene_header_policy.json" \
  --paired-manifest "$2" --out "$3" --workers "${IMMUNE_HEADER_WORKERS:-2}"
