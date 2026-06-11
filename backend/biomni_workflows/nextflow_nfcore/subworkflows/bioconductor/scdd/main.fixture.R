# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scDD", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scDD)
library(SingleCellExperiment)

# Load the example dataset from the scDD package
data(scDatExSim)

# Extract the normalized expression matrix
exprs_mat <- normcounts(scDatExSim)

# Extract the cell metadata
metadata <- as.data.frame(colData(scDatExSim))

# Write the expression matrix to a CSV file
write.csv(exprs_mat, file = "expression_matrix.csv", quote = FALSE)

# Write the metadata to a CSV file
write.csv(metadata, file = "metadata.csv", quote = FALSE)