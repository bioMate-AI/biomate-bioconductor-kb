#!/bin/bash -ue
# Mock mode: generate realistic MAGeCK count output
        python3 - <<'PYEOF'
import json, random, csv, os
random.seed(42)
n_guides = 500
n_cells  = 5000

# Simulate count table
with open("sample.count.txt", "w") as f:
    f.write("sgRNA\tGene\tsample\n")
    for i in range(n_guides):
        gene  = f"GENE{i//5+1:04d}"
        count = max(0, int(random.gauss(100, 30)))
        f.write(f"sg{gene}_{i%5+1}\t{gene}\t{count}\n")

# Simulated normalized count table
with open("sample.count_normalized.txt", "w") as f:
    f.write("sgRNA\tGene\tsample\n")
    for i in range(n_guides):
        gene  = f"GENE{i//5+1:04d}"
        count = max(0, int(random.gauss(1e6 / n_guides, 50)))
        f.write(f"sg{gene}_{i%5+1}\t{gene}\t{count}\n")

open("sample.count.log", "w").write(
    "Mock MAGeCK count log\n"
    "Total reads: 15000000\n"
    "Mapped: 13500000 (90.0%)\n"
)

qc = {
    "guide_library_coverage_pct"  : round(random.gauss(85, 5), 1),
    "transfection_efficiency_pct" : round(random.gauss(70, 8), 1),
    "total_reads"                 : 15000000,
    "mapped_reads"                : 13500000,
    "mapping_rate_pct"            : 90.0,
    "n_guides"                    : n_guides,
    "n_cells_estimated"           : n_cells,
}
json.dump(qc, open("mageck_count_summary.json", "w"), indent=2)
print(f"Mock MAGeCK count complete: {n_guides} guides, {n_cells} estimated cells")
PYEOF

        cat <<-END_VERSIONS > versions.yml
        "PERTURB_SEQ_ANALYSIS:MAGECK_COUNT":
            mageck: "0.5.9.5 (mock)"
            python: $(python3 --version | cut -d' ' -f2)
        END_VERSIONS
