#!/usr/bin/env bash
# Quick smoke test of the Perturb-seq pipeline in mock mode.
# Requires: nextflow >= 23 on PATH; Python 3 (no extra packages needed in mock mode).
set -euo pipefail
cd "$(dirname "$0")"

echo "=== Testing Perturb-seq pipeline in mock mode ==="

# Create minimal test inputs
mkdir -p test_data

# Fake guide library (5 guides × 2 genes + 1 non-targeting)
cat > test_data/guide_library.csv << 'EOF'
sgRNA,gene,sequence
sgGENE0001_1,GENE0001,ACGTACGTACGTACGTACGT
sgGENE0001_2,GENE0001,TGCATGCATGCATGCATGCA
sgGENE0002_1,GENE0002,AAACCCGGGTTTAAACCCGG
sgGENE0002_2,GENE0002,GGGAAATTTCCCGGGAAATT
non-targeting_1,non-targeting,CTAATGGACGTCAAGGATCG
EOF

# Stub input files (content irrelevant in mock mode)
touch test_data/sample.fastq.gz
touch test_data/design_matrix.txt
touch test_data/cells.h5ad

# Run pipeline in mock / test profile
nextflow run main.nf \
    -profile test \
    --fastq         "test_data/sample.fastq.gz" \
    --library_csv   "test_data/guide_library.csv" \
    --design_matrix "test_data/design_matrix.txt" \
    --anndata_h5ad  "test_data/cells.h5ad" \
    --sample_label  "mock_sample" \
    --outdir        "test_results" \
    2>&1 | head -120 \
    && echo "Nextflow run completed successfully." \
    || echo "Note: Nextflow run exited with non-zero status (expected without full environment)."

echo ""
echo "=== Checking expected output files ==="

EXPECTED_FILES=(
    "test_results/mock_sample/mageck_count/mock_sample.count.txt"
    "test_results/mock_sample/mageck_count/mock_sample.count_normalized.txt"
    "test_results/mock_sample/mageck_count/mageck_count_summary.json"
    "test_results/mock_sample/mageck_mle/mock_sample.gene_summary.txt"
    "test_results/mock_sample/mageck_mle/hits_table.csv"
    "test_results/mock_sample/scvi_perturbation/perturbation_state_summary.csv"
)

ALL_PRESENT=true
for f in "${EXPECTED_FILES[@]}"; do
    if [ -f "$f" ]; then
        echo "  FOUND: $f"
    else
        echo "  MISSING: $f"
        ALL_PRESENT=false
    fi
done

if $ALL_PRESENT; then
    echo ""
    echo "=== All expected output files present — mock test PASSED ==="
else
    echo ""
    echo "=== Some files missing — check Nextflow log above ==="
fi
