# Real user-style input for scry: a SingleCellExperiment of raw UMI counts
# (genes x cells) with genuine cell-type structure, exactly what a user obtains
# from their own droplet scRNA-seq pipeline (e.g. CellRanger). No ExperimentHub
# download / package demo data: we simulate structured counts so binomial
# deviance feature selection and GLM-PCA have real signal to recover.

suppressPackageStartupMessages(library(SingleCellExperiment))

set.seed(123)
n_genes <- 600
n_cells <- 120
n_types <- 4
types <- c("B-cells", "monocytes", "T-cells", "naive cytotoxic")
cell_type <- rep(types, length.out = n_cells)

# Each cell type over-expresses a distinct block of ~40 marker genes; remaining
# genes form a shared, lowly-expressed background. Library sizes vary per cell.
marker_blocks <- split(seq_len(n_types * 40), rep(seq_len(n_types), each = 40))
base_rate <- rep(0.3, n_genes)                       # background expression
libsize <- runif(n_cells, 0.6, 1.6)                  # per-cell capture efficiency

counts <- matrix(0L, nrow = n_genes, ncol = n_cells)
for (j in seq_len(n_cells)) {
    k <- match(cell_type[j], types)
    rate <- base_rate
    rate[marker_blocks[[k]]] <- 8                     # marker up-regulation
    counts[, j] <- rpois(n_genes, lambda = rate * libsize[j])
}
rownames(counts) <- sprintf("Gene%04d", seq_len(n_genes))
colnames(counts) <- sprintf("Cell%04d", seq_len(n_cells))

sce <- SingleCellExperiment(
    assays = list(counts = counts),
    colData = DataFrame(phenoid = cell_type, row.names = colnames(counts))
)

saveRDS(sce, "sce.rds")
file.copy("sce.rds", "sce", overwrite = TRUE)   # bare-token alias for staging
