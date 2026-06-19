#!/bin/bash
# Verify BIOC_QC_HARNESS inject blocks run cleanly under R against
# synthetic fixtures. Tests three representative workflows:
#   a4               — matrix-scan tier (missing-value handling)
#   biobroom         — object-type-aware tier (TMM + dispersion via DGEList)
#   batchqc          — declarative tier (batch-effect correction file-exists)
#
# For each: extract the inject block from the .nf file, materialize the
# expected fixture artifacts in a temp working dir, run Rscript on the
# block, and confirm qc_metrics.json is well-formed JSON with the
# expected labels in gates_by_label.
set -euo pipefail
ROOT=/home/yzhang/biomate
PYDONE=0

verify() {
    local name="$1"; local nf="$2"; local fixture_r="$3"; local expected_labels="$4"
    local dir=$(mktemp -d)
    cd "$dir"
    # Materialize fixture
    Rscript -e "$fixture_r" >/dev/null 2>&1 || { echo "  ✗ $name: fixture R failed"; return 1; }
    # Extract inject block
    python3 - <<EOF
import re
src = open("$ROOT/backend/biomni_workflows/$nf").read()
m = re.search(r'(\.qc_metrics_path\s*<-\s*"qc_metrics\.json".*?cat\(jsonlite::toJSON\(\.qc_payload[^)]*\)[^)]*\))', src, re.DOTALL)
block = m.group(1).replace("\\\$", "\$")  # un-escape Nextflow's \$ → R's $
open("block.R","w").write(block)
EOF
    # Run R block
    if Rscript block.R >stderr.log 2>&1; then
        if [ -f qc_metrics.json ]; then
            local labels=$(python3 -c "import json; d=json.load(open('qc_metrics.json')); print(','.join(d['gates_by_label'].keys()))")
            if [ "$labels" = "$expected_labels" ]; then
                local computed=$(python3 -c "import json; d=json.load(open('qc_metrics.json')); print(sum(1 for v in d['gates_by_label'].values() if v['status'].startswith('computed')))")
                local total=$(python3 -c "import json; d=json.load(open('qc_metrics.json')); print(len(d['gates_by_label']))")
                echo "  ✓ $name: labels match ($labels); $computed/$total computed"
            else
                echo "  ✗ $name: label mismatch. got=$labels expected=$expected_labels"
            fi
        else
            echo "  ✗ $name: no qc_metrics.json"; tail -5 stderr.log
        fi
    else
        echo "  ✗ $name: R block failed"; tail -10 stderr.log
    fi
    rm -rf "$dir"
}

echo "=== a4 (matrix-scan: missing-value handling) ==="
verify "a4" "nextflow_nfcore/subworkflows/bioconductor/a4/main.nf" \
  'set.seed(1); m <- matrix(rnorm(1000), 100, 10); m[sample(1000,20)] <- NA; saveRDS(m, "expr.rds")' \
  "missing-value handling"

echo "=== biobroom (object-aware: TMM + dispersion, no DGEList present → expect not_computed) ==="
verify "biobroom" "nextflow_nfcore/subworkflows/bioconductor/biobroom/main.nf" \
  'm <- matrix(rnorm(100), 10, 10); saveRDS(m, "plain.rds")' \
  "TMM normalization,dispersion/size-factor estimation"

echo "=== batchqc (declarative: batch-effect correction) ==="
verify "batchqc" "nextflow_nfcore/subworkflows/bioconductor/batchqc/main.nf" \
  'm <- matrix(rnorm(100), 10, 10); saveRDS(m, "corrected_expr.rds")' \
  "batch-effect correction"
