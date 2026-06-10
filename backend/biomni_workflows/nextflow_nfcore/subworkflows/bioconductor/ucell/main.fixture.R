# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("UCell", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(UCell)
library(Matrix)

# Load the sample dataset provided by UCell
data(sample.matrix, package = "UCell")

# The workflow expects files named 'sample.matrix' and 'exp.mat'
# Since they are sparse matrices (S4 objects), we serialize them using saveRDS
saveRDS(sample.matrix, file = "sample.matrix")

# For exp.mat, we avoid the ExperimentHub fetch (ZilionisLungData) to ensure offline execution.
# We reuse sample.matrix and modify it slightly to serve as exp.mat.
exp.mat <- sample.matrix
colnames(exp.mat) <- paste0("cell_", seq_len(ncol(exp.mat)))
saveRDS(exp.mat, file = "exp.mat")