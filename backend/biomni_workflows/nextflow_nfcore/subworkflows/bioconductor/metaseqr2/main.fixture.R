library(metaseqR2)

# Construct synthetic mm9GeneCounts
set.seed(123)
n_genes <- 100
gene_ids <- paste0("ENSMUSG", sprintf("%011d", 1:n_genes))

mm9GeneCounts <- data.frame(
    chromosome = rep("chr1", n_genes),
    start = seq(1, by = 5000, length.out = n_genes),
    end = seq(2000, by = 5000, length.out = n_genes),
    strand = rep("+", n_genes),
    gene_id = gene_ids,
    gc_content = runif(n_genes, 0.3, 0.7),
    biotype = rep("protein_coding", n_genes),
    gene_name = paste0("Gene", 1:n_genes),
    Cond1_1 = rpois(n_genes, lambda = 100),
    Cond1_2 = rpois(n_genes, lambda = 100),
    Cond2_1 = rpois(n_genes, lambda = 200),
    Cond2_2 = rpois(n_genes, lambda = 200),
    stringsAsFactors = FALSE
)
rownames(mm9GeneCounts) <- gene_ids

# Construct synthetic sampleListMm9
sampleListMm9 <- list(
    Cond1 = c("Cond1_1", "Cond1_2"),
    Cond2 = c("Cond2_1", "Cond2_2")
)

# Construct synthetic libsizeListMm9
libsizeListMm9 <- list(
    Cond1 = c(sum(mm9GeneCounts$Cond1_1), sum(mm9GeneCounts$Cond1_2)),
    Cond2 = c(sum(mm9GeneCounts$Cond2_1), sum(mm9GeneCounts$Cond2_2))
)

# Save to RDS files as expected by the workflow
saveRDS(mm9GeneCounts, "mm9GeneCounts.rds")
saveRDS(sampleListMm9, "sampleListMm9.rds")
saveRDS(libsizeListMm9, "libsizeListMm9.rds")