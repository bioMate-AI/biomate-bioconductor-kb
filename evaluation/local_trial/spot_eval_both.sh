#!/bin/bash
# Run BOTH removal evals on one box (efficient under GPU capacity scarcity):
#   1) sft-only control  (raw base + sft_adapter)
#   2) full_mix          (base_domain_mix + full_mix_adapter)
# against the CURRENT (fixed, tool-agnostic) removal_eval.jsonl. The launcher's user-data shuts the
# box down after this returns.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
echo "=== EVAL 1/2: sft-only (control) ==="
MODEL_SIZE=small STAGE=sft bash "$HERE/spot_eval.sh" || echo "sft eval returned nonzero"
echo "=== EVAL 2/2: full_mix ==="
MODEL_SIZE=small STAGE=full TAG=_mix bash "$HERE/spot_eval.sh" || echo "full_mix eval returned nonzero"
echo "BOTH_EVALS_DONE"
