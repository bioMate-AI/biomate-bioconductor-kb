# Real user-style input for scry on a large/HDF5-style dataset:
#   h5counts.rds - a DelayedArray-wrapped raw count matrix (the "on-disk large
#                  data" path scry supports). We use an in-memory DelayedArray
#                  seed so the .rds is fully self-contained (an HDF5Array .rds
#                  would only store a pointer to an external .h5 the harness does
#                  not stage), while still exercising scry's DelayedArray code.
#   sce.rds      - a SingleCellExperiment over the same counts.
# Structured counts (cell-type marker programs) so devianceFeatureSelection and
# nullResiduals have real signal. No ExperimentHub / package demo data.

suppressPackageStartupMessages({
  library(SingleCellExperiment)
  library(DelayedArray)
})

set.seed(101)
n_genes <- 400
n_cells <- 120
types <- c("B-cells", "monocytes", "T-cells")
cell_type <- sample(types, n_cells, replace = TRUE)

marker_blocks <- split(seq_len(length(types) * 30), rep(seq_len(length(types)), each = 30))
base_rate <- rep(0.3, n_genes)
libsize <- runif(n_cells, 0.6, 1.6)

mat <- matrix(0L, nrow = n_genes, ncol = n_cells)
for (j in seq_len(n_cells)) {
    k <- match(cell_type[j], types)
    rate <- base_rate
    rate[marker_blocks[[k]]] <- 8
    mat[, j] <- rpois(n_genes, lambda = rate * libsize[j])
}
rownames(mat) <- sprintf("Gene%04d", seq_len(n_genes))
colnames(mat) <- sprintf("Cell%04d", seq_len(n_cells))

h5counts <- DelayedArray(mat)
saveRDS(h5counts, "h5counts.rds")

sce <- SingleCellExperiment(assays = list(counts = h5counts))
colData(sce)$phenoid <- cell_type
saveRDS(sce, "sce.rds")
