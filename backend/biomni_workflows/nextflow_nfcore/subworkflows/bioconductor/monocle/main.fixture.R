# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("monocle", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(monocle)
    library(Biobase)
})

set.seed(123)

n_genes <- 100
n_cells <- 50

gene_ids <- paste0("ENSG000000", 10000:(10000 + n_genes - 1))
cell_ids <- paste0("Cell_", 1:n_cells)

# Expression matrix (counts)
exprs_mat <- matrix(rnbinom(n_genes * n_cells, size = 1, mu = 10), nrow = n_genes, ncol = n_cells)
rownames(exprs_mat) <- gene_ids
colnames(exprs_mat) <- cell_ids

# Cell metadata
pData_df <- data.frame(
    cell_id = cell_ids,
    Hours = sample(c(0, 24, 48, 72), n_cells, replace = TRUE),
    CellType = sample(c("TypeA", "TypeB"), n_cells, replace = TRUE),
    row.names = cell_ids
)

# Gene metadata
fData_df <- data.frame(
    gene_id = gene_ids,
    gene_short_name = paste0("Gene_", 1:n_genes),
    num_cells_expressed = rowSums(exprs_mat > 0),
    row.names = gene_ids
)

# Write to files
write.table(exprs_mat, "single_cell_expression_matrix.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(pData_df, "cell_metadata.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(fData_df, "gene_metadata.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)