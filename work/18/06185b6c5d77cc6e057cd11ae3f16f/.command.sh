#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json
import random
from datetime import datetime

random.seed(123)

drug_name   = "Imatinib"
target_gene = "BCR-ABL1"

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
        # Live: run fgsea against MSigDB Hallmark gene sets using the Wald stat
        # as gene-ranking metric (column "stat" in de_results.tsv).
        # ---------------------------------------------------------------------------
        Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(fgsea)
    library(data.table)
    library(jsonlite)
})

drug_name   <- "Imatinib"
target_gene <- "BCR-ABL1"
gmt_file    <- "/data/msigdb/h.all.v2023.2.Hs.symbols.gmt"

de_df <- read.table("de_results.tsv", header=TRUE, sep="\t", stringsAsFactors=FALSE)
de_df <- de_df[!is.na(de_df$stat), ]
ranks <- setNames(de_df$stat, de_df$gene_name)
ranks <- sort(ranks, decreasing=TRUE)

pathways  <- gmtPathways(gmt_file)

set.seed(42)
fgsea_res <- fgsea(
    pathways = pathways,
    stats    = ranks,
    minSize  = 15,
    maxSize  = 500,
    nperm    = 1000
)
fgsea_res <- fgsea_res[order(fgsea_res$padj), ]

fgsea_out                     <- fgsea_res[, c("pathway","NES","padj","pvalue","size","leadingEdge")]
fgsea_out$leading_edge_genes <- sapply(fgsea_out$leadingEdge, paste, collapse=",")
fgsea_out$description        <- fgsea_out$pathway

write.table(
    fgsea_out[, c("pathway","description","NES","padj","pvalue","size","leading_edge_genes")],
    file="enrichment.tsv", sep="\t", quote=FALSE, row.names=FALSE
)

top10     <- head(fgsea_res, 10)
rows_list <- lapply(seq_len(nrow(top10)), function(i) list(
    pathway            = top10$pathway[i],
    description        = top10$pathway[i],
    NES                = top10$NES[i],
    padj               = top10$padj[i],
    pvalue             = top10$pvalue[i],
    size               = top10$size[i],
    leading_edge_genes = paste(top10$leadingEdge[[i]], collapse=",")
))
payload <- list(
    drug_name   = drug_name,
    target_gene = target_gene,
    mock_mode   = FALSE,
    timestamp   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC"),
    pathways    = rows_list
)
write(toJSON(payload, auto_unbox=TRUE, pretty=TRUE), "enrichment_plot.json")

n_sig <- sum(fgsea_res$padj < 0.05, na.rm=TRUE)
cat(sprintf("fgsea (live): %d pathways tested, %d significant (padj<0.05)\n",
            nrow(fgsea_res), n_sig))
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "DRUG_MOA_RNASEQ:GENE_SET_ENRICHMENT":
        fgsea: $(Rscript -e "cat(as.character(packageVersion('fgsea')))" 2>/dev/null || echo "mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2 2>/dev/null || echo "3.10.0")
        mock_mode: "true"
    END_VERSIONS
