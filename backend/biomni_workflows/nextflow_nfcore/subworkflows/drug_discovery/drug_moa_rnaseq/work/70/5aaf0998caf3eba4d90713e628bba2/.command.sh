#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

drug_name   = "Erlotinib"
target_gene = "EGFR"
n_reps      = int("3")

# ---------------------------------------------------------------------------
# Biologically plausible kinase-pathway genes for kinase inhibitor targets
# ---------------------------------------------------------------------------
KINASE_GENES = [
    "MAPK1", "PIK3CA", "AKT1", "STAT3", "MYC",
    "CDK2",  "BCL2",   "EGFR", "KRAS",  "TP53",
    "MTOR",  "RAF1",   "BRAF", "JAK2",  "SRC",
    "RB1",   "CCND1",  "CDKN1A", "MDM2", "PTEN",
]

# Pad to 200 genes with generic identifiers
generic_genes = [f"GENE{i:04d}" for i in range(1, 181)]
all_genes     = KINASE_GENES + generic_genes
random.shuffle(all_genes)
all_genes     = all_genes[:200]

# ---------------------------------------------------------------------------
# Assign DE statistics
# ~20 % of genes are significantly DE (padj < 0.05, |log2FC| > 1).
# Kinase genes get stronger signal (80 % sig probability).
# ---------------------------------------------------------------------------
rows = []
for idx, gene_name in enumerate(all_genes, 1):
    is_kinase = gene_name in KINASE_GENES
    is_sig    = random.random() < (0.80 if is_kinase else 0.17)

    if is_sig:
        log2fc    = random.choice([-1, 1]) * random.uniform(1.0, 4.5 if is_kinase else 3.0)
        padj      = random.uniform(0.0001, 0.045)
        base_mean = random.uniform(500, 8000) if is_kinase else random.uniform(50, 3000)
        lfcse     = round(abs(log2fc) * random.uniform(0.08, 0.25), 4)
    else:
        log2fc    = random.uniform(-0.9, 0.9)
        padj      = random.uniform(0.052, 1.0)
        base_mean = random.uniform(10, 2000)
        lfcse     = round(abs(log2fc) * random.uniform(0.15, 0.4) + 0.01, 4)

    pvalue = min(padj * random.uniform(1.5, 8.0), 1.0)
    stat   = round(log2fc / (lfcse + 1e-6), 4)

    rows.append({
        "gene_id":        f"ENSG{idx:011d}",
        "gene_name":      gene_name,
        "log2FoldChange": round(log2fc, 4),
        "padj":           round(padj, 6),
        "pvalue":         round(pvalue, 6),
        "baseMean":       round(base_mean, 2),
        "lfcSE":          lfcse,
        "stat":           stat,
    })

rows.sort(key=lambda r: r["padj"])

# Write DE results TSV
header = "gene_id\tgene_name\tlog2FoldChange\tpadj\tpvalue\tbaseMean\tlfcSE\tstat"
with open("de_results.tsv", "w") as f:
    f.write(header + "\n")
    for r in rows:
        f.write(
            f"{r['gene_id']}\t{r['gene_name']}\t{r['log2FoldChange']}\t"
            f"{r['padj']}\t{r['pvalue']}\t{r['baseMean']}\t"
            f"{r['lfcSE']}\t{r['stat']}\n"
        )

# Volcano plot data JSON
points = []
for r in rows:
    neg_log10 = -math.log10(max(r["padj"], 1e-300))
    points.append({
        "gene_id":        r["gene_id"],
        "gene_name":      r["gene_name"],
        "log2FoldChange": r["log2FoldChange"],
        "neg_log10_padj": round(neg_log10, 4),
        "significant":    r["padj"] < 0.05 and abs(r["log2FoldChange"]) > 1,
    })

volcano = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   True,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "points":      points,
}
with open("volcano_data.json", "w") as f:
    json.dump(volcano, f, indent=2)

n_sig = sum(1 for r in rows if r["padj"] < 0.05 and abs(r["log2FoldChange"]) > 1)
print(f"DE analysis (mock): {len(rows)} genes tested, {n_sig} significantly DE")
print(f"  Drug: {drug_name}  Target: {target_gene}  n_replicates: {n_reps}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: run pydeseq2 (Python DESeq2) on pre-supplied count-matrix TSV files.
        # Each TSV: rows = genes, columns = samples, first column = gene_id (header).
        # pydeseq2 is a faithful Python reimplementation of DESeq2 (Muzellec et al. 2022).
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json, math, sys
import numpy as np
import pandas as pd
from datetime import datetime, timezone

drug_name   = "Erlotinib"
target_gene = "EGFR"

# ── Load count matrices ──────────────────────────────────────────────────────
treated_df = pd.read_csv("test_treated_counts.tsv", sep="\t", index_col=0)
control_df = pd.read_csv("test_control_counts.tsv", sep="\t", index_col=0)

counts_df  = pd.concat([treated_df, control_df], axis=1)
n_treated  = treated_df.shape[1]
n_control  = control_df.shape[1]
conditions = ["treated"] * n_treated + ["control"] * n_control

meta_df = pd.DataFrame({"condition": conditions}, index=counts_df.columns)

print(f"Loaded counts: {counts_df.shape[0]} genes x {counts_df.shape[1]} samples")
print(f"  Treated samples: {n_treated}  Control samples: {n_control}")

# ── Run pydeseq2 ─────────────────────────────────────────────────────────────
from pydeseq2.dds import DeseqDataSet
from pydeseq2.ds  import DeseqStats

counts_int = counts_df.T.astype(int)   # pydeseq2 expects samples x genes
dds = DeseqDataSet(
    counts   = counts_int,
    metadata = meta_df,
    design_factors = "condition",
    ref_level      = ["condition", "control"],
    n_cpus         = 4,
    quiet          = False,
)
dds.deseq2()

stat_res = DeseqStats(dds, contrast=["condition", "treated", "control"], quiet=False)
stat_res.summary()

res_df = stat_res.results_df.copy()
res_df.index.name = "gene_id"
res_df["gene_name"] = res_df.index
res_df = res_df.dropna(subset=["padj"]).sort_values("padj")

# ── Write DE results TSV ─────────────────────────────────────────────────────
out_cols = ["gene_name", "log2FoldChange", "padj", "pvalue", "baseMean", "lfcSE", "stat"]
out_cols = [c for c in out_cols if c in res_df.columns]
res_df.reset_index()[["gene_id"] + out_cols].to_csv("de_results.tsv", sep="\t", index=False)

# ── Write volcano JSON ────────────────────────────────────────────────────────
points = []
for gene_id, row in res_df.iterrows():
    points.append({
        "gene_id":        gene_id,
        "gene_name":      row.get("gene_name", gene_id),
        "log2FoldChange": float(row["log2FoldChange"]) if not math.isnan(row["log2FoldChange"]) else 0.0,
        "neg_log10_padj": float(-math.log10(max(row["padj"], 1e-300))),
        "significant":    bool(row["padj"] < 0.05 and abs(row["log2FoldChange"]) > 1),
    })

volcano = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   False,
    "timestamp":   datetime.now(timezone.utc).isoformat(),
    "points":      points,
}
with open("volcano_data.json", "w") as f:
    json.dump(volcano, f, indent=2)

n_sig = sum(1 for p in points if p["significant"])
print(f"DE analysis (live/pydeseq2): {len(res_df)} genes tested, {n_sig} significantly DE")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "DRUG_MOA_RNASEQ:DIFFERENTIAL_EXPRESSION":
        deseq2: $(Rscript -e "cat(as.character(packageVersion('DESeq2')))" 2>/dev/null || echo "mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2 2>/dev/null || echo "3.10.0")
        mock_mode: "false"
    END_VERSIONS
