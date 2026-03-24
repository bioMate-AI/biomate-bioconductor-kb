#!/bin/bash -ue
if [ "false" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(123)

drug_name   = "Erlotinib"
target_gene = "EGFR"

# ---------------------------------------------------------------------------
# Biologically plausible MSigDB Hallmark pathways for a kinase inhibitor.
# Base NES values reflect expected biology (positive = up-regulated on drug).
# ---------------------------------------------------------------------------
HALLMARK_PATHWAYS = [
    ("HALLMARK_E2F_TARGETS",               "cell cycle / DNA replication",        2.31),
    ("HALLMARK_G2M_CHECKPOINT",            "G2/M cell cycle checkpoint",           2.18),
    ("HALLMARK_MYC_TARGETS_V1",            "MYC transcriptional targets",          1.95),
    ("HALLMARK_PI3K_AKT_MTOR_SIGNALING",   "PI3K/AKT/mTOR pathway",               1.72),
    ("HALLMARK_APOPTOSIS",                 "programmed cell death",               -1.88),
    ("HALLMARK_P53_PATHWAY",               "TP53 tumour-suppressor pathway",      -2.05),
    ("HALLMARK_DNA_REPAIR",                "DNA damage response",                  1.44),
    ("HALLMARK_OXIDATIVE_PHOSPHORYLATION", "mitochondrial oxidative phosphorylation", -1.31),
    ("HALLMARK_INFLAMMATORY_RESPONSE",     "innate immune / inflammatory response",-1.52),
    ("HALLMARK_UNFOLDED_PROTEIN_RESPONSE", "ER stress / unfolded protein response", 1.19),
]

# Collect significant DE gene names for leading-edge annotation
sig_genes = []
with open("de_results.tsv") as fh:
    next(fh)  # skip header
    for line in fh:
        parts = line.strip().split("\t")
        if len(parts) >= 4:
            try:
                padj   = float(parts[3])
                log2fc = float(parts[2])
                if padj < 0.05 and abs(log2fc) > 1:
                    sig_genes.append(parts[1])
            except ValueError:
                pass

if not sig_genes:
    sig_genes = ["MAPK1", "AKT1", "MYC", "STAT3", "CDK2"]

rows = []
for pathway, description, base_nes in HALLMARK_PATHWAYS:
    nes       = round(base_nes + random.uniform(-0.15, 0.15), 3)
    padj      = round(random.uniform(0.001, 0.048), 4)
    pvalue    = round(padj * random.uniform(1.2, 5.0), 6)
    size      = random.randint(80, 350)
    n_leading = min(random.randint(5, 20), len(sig_genes))
    leading   = ",".join(random.sample(sig_genes, n_leading)) if n_leading > 0 else ""
    rows.append({
        "pathway":            pathway,
        "description":        description,
        "NES":                nes,
        "padj":               padj,
        "pvalue":             pvalue,
        "size":               size,
        "leading_edge_genes": leading,
    })

rows.sort(key=lambda r: abs(r["NES"]), reverse=True)

# Write enrichment TSV
header = "pathway\tdescription\tNES\tpadj\tpvalue\tsize\tleading_edge_genes"
with open("enrichment.tsv", "w") as f:
    f.write(header + "\n")
    for r in rows:
        f.write(
            f"{r['pathway']}\t{r['description']}\t{r['NES']}\t"
            f"{r['padj']}\t{r['pvalue']}\t{r['size']}\t{r['leading_edge_genes']}\n"
        )

# Write enrichment plot JSON
plot_data = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   True,
    "timestamp":   datetime.utcnow().isoformat() + "Z",
    "pathways":    rows,
}
with open("enrichment_plot.json", "w") as f:
    json.dump(plot_data, f, indent=2)

print(f"GSEA (mock): {len(rows)} Hallmark pathways enriched for {drug_name}")
for r in rows[:5]:
    direction = "UP" if r["NES"] > 0 else "DOWN"
    print(f"  [{direction}] {r['pathway']}  NES={r['NES']}  padj={r['padj']}")
EOF

    else
        # ---------------------------------------------------------------------------
        # Live: run gseapy prerank against MSigDB Hallmark gene sets.
        # gseapy is a Python GSEA implementation wrapping the GSEA Java algorithm.
        # Uses Wald stat from DE results as the gene ranking metric.
        # ---------------------------------------------------------------------------
        python3 << 'PYEOF'
import json, math, os
import pandas as pd
import gseapy as gp
from datetime import datetime, timezone

drug_name   = "Erlotinib"
target_gene = "EGFR"
gmt_file    = "null"

de_df = pd.read_csv("de_results.tsv", sep="\t")
de_df = de_df.dropna(subset=["stat"])
de_df = de_df.sort_values("stat", ascending=False)

ranking = de_df.set_index("gene_name")["stat"].to_dict()
ranking_series = pd.Series(ranking).sort_values(ascending=False)

# Choose gene set source: use provided GMT file if it exists, otherwise use gseapy's
# built-in MSigDB Hallmark collection (fetched on demand from gseapy's cached sets).
if os.path.exists(gmt_file):
    gene_sets = gmt_file
    print(f"Using local GMT file: {gmt_file}")
else:
    gene_sets = "MSigDB_Hallmark_2020"
    print(f"GMT file not found at {gmt_file}; using gseapy built-in: {gene_sets}")

pre_res = gp.prerank(
    rnk          = ranking_series,
    gene_sets    = gene_sets,
    min_size     = 1,     # accept any overlap — filter by FDR at interpretation step
    max_size     = 500,
    permutation_num = 200,
    seed         = 42,
    verbose      = True,
    outdir       = None,
)

res_df = pre_res.res2d.copy()
res_df = res_df.rename(columns={
    "Term": "pathway", "NES": "NES", "FDR q-val": "padj",
    "NOM p-val": "pvalue", "Tag %": "tag_pct", "Lead_genes": "leading_edge_genes",
})
if "pathway" not in res_df.columns and "Term" not in res_df.columns:
    res_df = res_df.reset_index().rename(columns={"index": "pathway"})
res_df["description"] = res_df["pathway"]

for col in ["padj", "pvalue", "NES"]:
    if col in res_df.columns:
        res_df[col] = pd.to_numeric(res_df[col], errors="coerce")

res_df = res_df.sort_values("padj")

out_cols = [c for c in ["pathway","description","NES","padj","pvalue","leading_edge_genes"] if c in res_df.columns]
res_df[out_cols].to_csv("enrichment.tsv", sep="\t", index=False)

rows = []
for _, row in res_df.head(10).iterrows():
    rows.append({
        "pathway":            str(row.get("pathway", "")),
        "description":        str(row.get("description", "")),
        "NES":                float(row["NES"]) if not math.isnan(float(row["NES"])) else 0.0,
        "padj":               float(row["padj"]) if not math.isnan(float(row["padj"])) else 1.0,
        "pvalue":             float(row.get("pvalue", 1.0)) if "pvalue" in row else 1.0,
        "leading_edge_genes": str(row.get("leading_edge_genes", "")),
    })

plot_data = {
    "drug_name":   drug_name,
    "target_gene": target_gene,
    "mock_mode":   False,
    "timestamp":   datetime.now(timezone.utc).isoformat(),
    "pathways":    rows,
}
with open("enrichment_plot.json", "w") as f:
    json.dump(plot_data, f, indent=2)

n_sig = int((res_df["padj"] < 0.05).sum()) if "padj" in res_df.columns else 0
print(f"GSEA (live/gseapy): {len(res_df)} pathways, {n_sig} significant (padj<0.05)")
for r in rows[:5]:
    direction = "UP" if r["NES"] > 0 else "DOWN"
    print(f"  [{direction}] {r['pathway']}  NES={r['NES']:.3f}  padj={r['padj']:.4f}")
PYEOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "DRUG_MOA_RNASEQ:GENE_SET_ENRICHMENT":
        fgsea: $(Rscript -e "cat(as.character(packageVersion('fgsea')))" 2>/dev/null || echo "mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2 2>/dev/null || echo "3.10.0")
        mock_mode: "false"
    END_VERSIONS
