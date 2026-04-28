#!/bin/bash -ue
if [ "true" = "true" ]; then
        python3 << 'EOF'
import json
import math
import random
from datetime import datetime

random.seed(42)

drug_name   = "Imatinib"
target_gene = "BCR-ABL1"
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
        # Live: run DESeq2 on pre-supplied count-matrix TSV files.
        # Each TSV: genes as rows (row names), samples as columns (header required).
        # ---------------------------------------------------------------------------
        Rscript - << 'REOF'
suppressPackageStartupMessages({
    library(DESeq2)
    library(jsonlite)
})

drug_name   <- "Imatinib"
target_gene <- "BCR-ABL1"
n_reps      <- as.integer("3")

treated_mat <- read.table("mock_treated_counts.tsv", header=TRUE, sep="\t", row.names=1, check.names=FALSE)
control_mat <- read.table("mock_control_counts.tsv", header=TRUE, sep="\t", row.names=1, check.names=FALSE)

counts   <- cbind(treated_mat, control_mat)
cond     <- factor(c(rep("treated", ncol(treated_mat)), rep("control", ncol(control_mat))))
col_data <- data.frame(condition=cond, row.names=colnames(counts))

dds <- DESeqDataSetFromMatrix(countData=round(counts), colData=col_data, design=~condition)
dds <- DESeq(dds)
res <- results(dds, contrast=c("condition", "treated", "control"))

res_df            <- as.data.frame(res)
res_df$gene_id   <- rownames(res_df)
res_df$gene_name <- rownames(res_df)
res_df            <- res_df[!is.na(res_df$padj), ]
res_df            <- res_df[order(res_df$padj), ]

write.table(
    res_df[, c("gene_id","gene_name","log2FoldChange","padj","pvalue","baseMean","lfcSE","stat")],
    file="de_results.tsv", sep="\t", quote=FALSE, row.names=FALSE
)

volcano_pts <- lapply(seq_len(nrow(res_df)), function(i) list(
    gene_id        = res_df$gene_id[i],
    gene_name      = res_df$gene_name[i],
    log2FoldChange = res_df$log2FoldChange[i],
    neg_log10_padj = -log10(max(res_df$padj[i], 1e-300)),
    significant    = res_df$padj[i] < 0.05 & abs(res_df$log2FoldChange[i]) > 1
))

payload <- list(
    drug_name   = drug_name,
    target_gene = target_gene,
    mock_mode   = FALSE,
    timestamp   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC"),
    points      = volcano_pts
)
write(toJSON(payload, auto_unbox=TRUE, pretty=TRUE), "volcano_data.json")

n_sig <- sum(res_df$padj < 0.05 & abs(res_df$log2FoldChange) > 1, na.rm=TRUE)
cat(sprintf("DE analysis (live): %d genes tested, %d significantly DE\n", nrow(res_df), n_sig))
REOF
    fi

    cat <<-END_VERSIONS > versions.yml
    "DRUG_MOA_RNASEQ:DIFFERENTIAL_EXPRESSION":
        deseq2: $(Rscript -e "cat(as.character(packageVersion('DESeq2')))" 2>/dev/null || echo "mock")
        python: $(python3 --version 2>&1 | cut -d' ' -f2 2>/dev/null || echo "3.10.0")
        mock_mode: "true"
    END_VERSIONS
