# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("sigFeature", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(sigFeature)
library(SummarizedExperiment)

# Load the example dataset from the sigFeature package
data("ExampleRawData", package = "sigFeature")

# Extract the expression matrix (features as rows, samples as columns)
expr_matrix <- assays(ExampleRawData)$counts

# Extract the sample metadata (containing binary class labels)
sample_metadata <- as.data.frame(colData(ExampleRawData))

# Write the expression matrix to a CSV file
write.csv(expr_matrix, file = "expression_matrix.csv", row.names = TRUE)

# Write the sample metadata to a CSV file
write.csv(sample_metadata, file = "sample_metadata.csv", row.names = TRUE)