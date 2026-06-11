# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GSVA", "Matrix", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GSVA)
library(Matrix)
library(SingleCellExperiment)

set.seed(123)

p <- 10000 ## number of genes
n <- 30 ## number of samples
## simulate expression values from a standard Gaussian distribution
X <- matrix(rnorm(p*n), nrow=p, dimnames=list(paste0("g", 1:p), paste0("s", 1:n)))

## sample gene set sizes
gs <- as.list(sample(10:100, size=100, replace=TRUE))
## sample gene sets
gs <- lapply(gs, function(n, p) paste0("g", sample(1:p, size=n, replace=FALSE)), p)
names(gs) <- paste0("gs", 1:length(gs))

# Serialize to sc_counts.rds as a SingleCellExperiment with a sparse matrix
X_sparse <- Matrix(X, sparse = TRUE)
sce <- SingleCellExperiment(assays = list(counts = X_sparse))
saveRDS(sce, "sc_counts.rds")

# Serialize to cell_type_signatures.gmt
gmt_lines <- sapply(names(gs), function(set_name) {
  paste(c(set_name, "simulated_geneset", gs[[set_name]]), collapse = "\t")
})
writeLines(gmt_lines, "cell_type_signatures.gmt")