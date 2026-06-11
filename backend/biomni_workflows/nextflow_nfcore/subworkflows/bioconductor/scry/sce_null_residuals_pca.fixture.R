# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(SingleCellExperiment))

# Construct a synthetic SingleCellExperiment object to avoid offline ExperimentHub fetch failures
set.seed(123)
counts_mat <- matrix(rpois(5000, lambda = 1), nrow = 500, ncol = 10)
rownames(counts_mat) <- paste0("Gene", 1:500)
colnames(counts_mat) <- paste0("Cell", 1:10)

col_data <- data.frame(
    phenoid = rep(c("B-cell", "T-cell"), each = 5),
    row.names = colnames(counts_mat)
)

sce <- SingleCellExperiment(
    assays = list(counts = counts_mat),
    colData = col_data
)

saveRDS(sce, "sce")