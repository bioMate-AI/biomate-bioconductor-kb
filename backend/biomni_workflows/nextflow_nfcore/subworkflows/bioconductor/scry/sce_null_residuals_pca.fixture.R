# Real user-style input for scry null-residuals + PCA: a SingleCellExperiment of
# raw UMI counts with genuine cell-type structure (a user's CellRanger output).
# Structured (not flat-Poisson) counts so binomial deviance, deviance/Pearson
# null residuals and PCA all have real signal. No ExperimentHub / demo data.

suppressPackageStartupMessages(library(SingleCellExperiment))

set.seed(123)
n_genes <- 500
n_cells <- 100
types <- c("B-cell", "T-cell", "monocyte", "NK")
cell_type <- rep(types, length.out = n_cells)

marker_blocks <- split(seq_len(length(types) * 35), rep(seq_len(length(types)), each = 35))
base_rate <- rep(0.3, n_genes)
libsize <- runif(n_cells, 0.6, 1.6)

counts <- matrix(0L, nrow = n_genes, ncol = n_cells)
for (j in seq_len(n_cells)) {
    k <- match(cell_type[j], types)
    rate <- base_rate
    rate[marker_blocks[[k]]] <- 8
    counts[, j] <- rpois(n_genes, lambda = rate * libsize[j])
}
rownames(counts) <- sprintf("Gene%04d", seq_len(n_genes))
colnames(counts) <- sprintf("Cell%04d", seq_len(n_cells))

sce <- SingleCellExperiment(
    assays = list(counts = counts),
    colData = DataFrame(phenoid = cell_type, row.names = colnames(counts))
)

saveRDS(sce, "sce.rds")
file.copy("sce.rds", "sce", overwrite = TRUE)
