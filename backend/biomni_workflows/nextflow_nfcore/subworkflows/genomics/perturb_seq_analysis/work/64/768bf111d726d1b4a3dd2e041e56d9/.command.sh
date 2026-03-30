#!/bin/bash -ue
python3 - <<'PYEOF'
import random, csv
random.seed(42)
n_genes = 100

# Gene summary in MAGeCK MLE format
with open("sample.gene_summary.txt", "w") as f:
    f.write("Gene\tbeta\tz\tp.value\tFDR\n")
    for i in range(n_genes):
        gene = f"GENE{i+1:04d}"
        beta = random.gauss(0, 1)
        z    = beta / 0.3
        p    = max(1e-10, min(1, abs(random.gauss(0.05, 0.1))))
        fdr  = min(1, p * n_genes / (i + 1))
        f.write(f"{gene}\t{beta:.4f}\t{z:.4f}\t{p:.6f}\t{fdr:.6f}\n")

open("sample.sgrna_summary.txt", "w").write("sgRNA\tGene\tLFC\n")

# Curated hits table (FDR < 0.1 flagged)
with open("hits_table.csv", "w") as f:
    w = csv.writer(f)
    w.writerow(["gene", "beta", "z_score", "p_value", "FDR", "significant"])
    for i in range(n_genes):
        gene = f"GENE{i+1:04d}"
        beta = random.gauss(0, 1)
        fdr  = max(0.001, random.uniform(0, 0.3))
        sig  = "True" if fdr < 0.1 else "False"
        w.writerow([gene, f"{beta:.4f}", f"{beta/0.3:.4f}",
                    f"{fdr*0.1:.6f}", f"{fdr:.6f}", sig])

print("Mock MAGeCK MLE complete: 100 genes analyzed")
PYEOF

        cat <<-END_VERSIONS > versions.yml
        "PERTURB_SEQ_ANALYSIS:MAGECK_MLE":
            mageck: "0.5.9.5 (mock)"
            python: $(python3 --version | cut -d' ' -f2)
        END_VERSIONS
