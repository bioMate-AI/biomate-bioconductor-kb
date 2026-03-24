#!/bin/bash -ue
export NUMBA_CACHE_DIR=/tmp/numba_cache
        export MPLCONFIGDIR=/tmp/matplotlib
        mkdir -p /tmp/numba_cache /tmp/matplotlib

        python3 - <<'PYEOF'
import csv, random
random.seed(42)

n_cells         = 500
n_perturbations = 20

with open("perturbation_state_summary.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["perturbation", "n_cells", "mean_embedding_shift", "signature_score"])
    for i in range(n_perturbations):
        name  = f"GENE{i+1:04d}_sg1" if i < n_perturbations - 1 else "non-targeting"
        n     = random.randint(20, 80)
        shift = random.gauss(0.5, 0.3) if i < 10 else random.gauss(0.1, 0.05)
        score = max(0.0, shift + random.gauss(0, 0.1))
        w.writerow([name, n, round(shift, 3), round(score, 3)])

# Placeholder output files — real run produces proper h5ad / PNG
open("scvi_perturbation_emb.h5ad", "w").write("MOCK_H5AD_PLACEHOLDER")
open("umap_perturbation.png",      "w").write("MOCK_PNG_PLACEHOLDER")

print(f"Mock scVI perturbation: {n_cells} cells, {n_perturbations} perturbations")
PYEOF

        cat <<-END_VERSIONS > versions.yml
        "PERTURB_SEQ_ANALYSIS:SCVI_PERTURBATION":
            python: $(python3 --version | cut -d' ' -f2)
            scvi_tools: "mock"
        END_VERSIONS
